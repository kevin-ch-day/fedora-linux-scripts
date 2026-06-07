#!/usr/bin/env bash
# lib/errors.sh — shared error handling helpers for the Fedora toolkit
# Version: 0.2.0
#
# Loaded automatically via lib/common.sh. Direct source also supported.
#
# Traps:     errors_init_script, error_cleanup_add, errors_mktemp_dir
# Run:        run_or_die, require_ok, try_run, warn_if_fail, retry, errors_wait_until
# Validate:   assert_file, assert_dir, assert_cmds, die_with_hint, die_unknown_option
# Collect:    errors_issue_reset, errors_issue_add, errors_issue_summary
# DNF:        errors_check_dnf_repos, errors_dnf_hint (used by lib/packages.sh pkg_dnf_run)
#
# Do not execute directly.

if [[ -n "${FEDORA_ERRORS_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_ERRORS_SH_LOADED=1

_ERRORS_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_ERRORS_LIB_DIR}/common.sh"

# ---------- configuration ----------
ERRORS_SCRIPT_LABEL="${ERRORS_SCRIPT_LABEL:-}"
ERRORS_TRAP_INSTALLED="${ERRORS_TRAP_INSTALLED:-0}"
ERRORS_ERRTRACE="${ERRORS_ERRTRACE:-1}"
ERRORS_SHOW_LINE="${ERRORS_SHOW_LINE:-1}"

_error_cleanup_cmds=()
_errors_failed=0
_errors_issues=()

# ---------- internal ----------
_errors_log() {
  local level="$1"
  shift
  if [[ "${level}" == ERROR ]] && declare -F log_error >/dev/null 2>&1; then
    log_error "$@"
  fi
}

_errors_on_err() {
  local rc=$?
  local line="${BASH_LINENO[0]:-?}"
  local cmd="${BASH_COMMAND:-?}"
  _errors_failed=1

  if [[ -n "${ERRORS_SCRIPT_LABEL}" ]]; then
    _errors_log ERROR "${ERRORS_SCRIPT_LABEL}: command failed (exit ${rc})"
  else
    _errors_log ERROR "Command failed (exit ${rc})"
  fi

  if [[ "${ERRORS_SHOW_LINE}" == 1 ]]; then
    err "  at line ${line}: ${cmd}"
  fi
  [[ -n "${ERRORS_HINT:-}" ]] && err "  hint: ${ERRORS_HINT}"

  exit "${rc}"
}

_errors_on_exit() {
  local rc=$?
  errors_run_cleanups
  if [[ -n "${_ERRORS_PREV_EXIT_CMD:-}" ]]; then
    # shellcheck disable=SC2090
    eval "${_ERRORS_PREV_EXIT_CMD}"
    return
  fi
  exit "${rc}"
}

errors_run_cleanups() {
  local cmd=""
  for (( _i=${#_error_cleanup_cmds[@]}-1; _i>=0; _i-- )); do
    cmd="${_error_cleanup_cmds[_i]}"
    # shellcheck disable=SC2090,SC2086
    eval "${cmd}" || true
  done
}

_errors_ensure_exit_trap() {
  if [[ "${_ERRORS_EXIT_TRAP_INSTALLED:-}" == 1 ]]; then
    return 0
  fi
  _ERRORS_EXIT_TRAP_INSTALLED=1
  if trap -p EXIT 2>/dev/null | grep -q EXIT; then
    _ERRORS_PREV_EXIT_CMD="$(trap -p EXIT | sed -n "s/^trap -- '\\(.*\\)' EXIT\$/\\1/p")"
  fi
  trap '_errors_on_exit' EXIT
}

# ---------- traps / lifecycle ----------
errors_init_script() {
  local label="${1:-${0##*/}}"
  ERRORS_SCRIPT_LABEL="${label}"

  if [[ "${ERRORS_TRAP_INSTALLED}" == 1 ]]; then
    return 0
  fi
  ERRORS_TRAP_INSTALLED=1

  if [[ "${ERRORS_ERRTRACE}" == 1 ]]; then
    set -o errtrace 2>/dev/null || true
  fi

  trap '_errors_on_err' ERR
}

error_cleanup_add() {
  local cmd="${1:?cleanup command required}"
  _error_cleanup_cmds+=("${cmd}")
  _errors_ensure_exit_trap
}

errors_mktemp_dir() {
  local __var="${1:?variable name required}"
  local tmp=""
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/fedora-toolkit.XXXXXX")"
  error_cleanup_add "rm -rf -- '${tmp}'"
  printf -v "${__var}" '%s' "${tmp}"
}

errors_hint() {
  ERRORS_HINT="$*"
}

errors_clear_hint() {
  ERRORS_HINT=""
}

# ---------- run helpers ----------
run_or_die() {
  local ctx="$1"
  shift
  local rc=0
  "$@" || rc=$?
  (( rc == 0 )) || die "${ctx} (exit ${rc})"
}

require_ok() {
  run_or_die "$@"
}

try_run() {
  "$@" && return 0
  return $?
}

warn_if_fail() {
  local ctx="$1"
  shift
  local rc=0
  "$@" || rc=$?
  if (( rc != 0 )); then
    warn "${ctx} (exit ${rc}) — continuing"
  fi
  return "${rc}"
}

retry() {
  local attempts="${1:?attempt count required}"
  local delay="${2:?delay seconds required}"
  shift 2
  local n=1 rc=0

  while (( n <= attempts )); do
    "$@" && return 0
    rc=$?
    if (( n >= attempts )); then
      break
    fi
    warn "Attempt ${n}/${attempts} failed (exit ${rc}); retry in ${delay}s: $*"
    sleep "${delay}"
    n=$(( n + 1 ))
  done
  return "${rc}"
}

# Poll until command succeeds or attempts exhausted (container readiness, locks, etc.).
errors_wait_until() {
  local attempts="${1:?attempt count required}"
  local delay="${2:?delay seconds required}"
  local ctx="${3:?context required}"
  shift 3
  local i=0

  while (( i < attempts )); do
    if "$@"; then
      return 0
    fi
    i=$(( i + 1 ))
    if (( i >= attempts )); then
      break
    fi
    sleep "${delay}"
  done
  die_with_hint "${ctx} (timed out after ${attempts} attempts)" \
    "Inspect logs above, then retry or run the lane doctor."
}

# ---------- DNF / repo hygiene ----------
errors_check_dnf_repos() {
  local f bad=0
  shopt -s nullglob
  for f in /etc/yum.repos.d/*.repo; do
    if [[ ! -r "${f}" ]]; then
      warn "DNF repo file not readable: ${f}"
      bad=1
    fi
  done
  shopt -u nullglob
  if (( bad )); then
    if [[ "${EUID}" -ne 0 ]]; then
      warn "Use sudo for install scripts, or fix repo file permissions (often stale third-party repos)."
    else
      warn "Fix or remove unreadable repo files under /etc/yum.repos.d before running dnf."
    fi
  fi
}

errors_dnf_hint() {
  errors_hint "Check /etc/yum.repos.d/*.repo permissions, then: sudo dnf clean all && sudo dnf makecache"
}

# ---------- issue collector (doctors / batch installs) ----------
errors_issue_reset() {
  _errors_issues=()
}

errors_issue_add() {
  local section="${1:?section required}"
  local msg="${2:?message required}"
  _errors_issues+=("${section}|${msg}")
}

errors_issue_count() {
  printf '%s\n' "${#_errors_issues[@]}"
}

errors_issue_summary() {
  local title="${1:-Issues found}"
  local entry sec msg

  if ((${#_errors_issues[@]} == 0)); then
    return 0
  fi

  err "${title} (${#_errors_issues[@]}):"
  for entry in "${_errors_issues[@]}"; do
    sec="${entry%%|*}"
    msg="${entry#*|}"
    err "  [${sec}] ${msg}"
  done
  return 1
}

# ---------- CLI / options ----------
die_unknown_option() {
  local opt="${1:?option required}"
  local hint="${2:-Try --help}"
  die_with_hint "Unknown option: ${opt}" "${hint}"
}

# ---------- validation ----------
assert_nonempty() {
  local value="${1:-}"
  local msg="${2:-Value required}"
  [[ -n "${value}" ]] || die "${msg}"
}

assert_file() {
  local path="$1"
  local msg="${2:-Missing file: ${path}}"
  [[ -f "${path}" ]] || die "${msg}"
}

assert_dir() {
  local path="$1"
  local msg="${2:-Missing directory: ${path}}"
  [[ -d "${path}" ]] || die "${msg}"
}

assert_readable() {
  local path="$1"
  local msg="${2:-Not readable: ${path}}"
  [[ -r "${path}" ]] || die "${msg}"
}

assert_cmds() {
  local c=""
  for c in "$@"; do
    cmd_available "${c}" || die "Missing required command: ${c}"
  done
}

die_with_hint() {
  local msg="$1"
  local hint="$2"
  err "${msg}"
  [[ -n "${hint}" ]] && err "Hint: ${hint}"
  exit 1
}

die_with_usage() {
  local msg="$1"
  err "${msg}"
  if declare -F usage >/dev/null 2>&1; then
    usage >&2
  fi
  exit 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
