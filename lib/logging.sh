#!/usr/bin/env bash
# lib/logging.sh — Fedora toolkit logging engine
# Version: 0.3.2
#
# Engine API (write path):
#   init_script_logging FILE SCRIPT TITLE     — tee session + EXIT trap
#   log_info / log_warn / log_error / log_debug — structured lines
#   log_step N TOTAL MSG                      — numbered progress lines
#   log_cmd ...                               — run command, log exit code
#
# Engine API (read/maintenance):
#   log_summary FILE | log_grep_issues FILE | log_archive_file FILE
#   log_rotate_if_large FILE MB
#
# Policy: see logs/README.md
#
# Do not execute directly.

if [[ -n "${FEDORA_LOGGING_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_LOGGING_SH_LOADED=1

_LOG_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_LOG_LIB_DIR}/common.sh"

# ---------- registry (stable log filenames; consumed by task scripts) ----------
FEDORA_LOG_SYSTEM_UPDATE="system_update.log"
# shellcheck disable=SC2034
FEDORA_LOG_REBUILD="fedora_rebuild.log"
# shellcheck disable=SC2034
FEDORA_LOG_ANDROID_CORE="android_dev_core.log"
# shellcheck disable=SC2034
FEDORA_LOG_MOBSF="mobsf.log"

# ---------- engine state ----------
FEDORA_LOG_LEVEL="${FEDORA_LOG_LEVEL:-INFO}"   # DEBUG | INFO | WARN | ERROR
FEDORA_LOG_SESSION_ID="${FEDORA_LOG_SESSION_ID:-}"
FEDORA_LOG_TEE_ACTIVE="${FEDORA_LOG_TEE_ACTIVE:-0}"
FEDORA_LOG_SCRIPT_NAME="${FEDORA_LOG_SCRIPT_NAME:-}"

# Optional: auto-archive when log exceeds N MB before new session (0 = off).
FEDORA_LOG_ROTATE_MB="${FEDORA_LOG_ROTATE_MB:-0}"

# ---------- internal helpers ----------
_log_level_rank() {
  case "${1^^}" in
    DEBUG) echo 0 ;;
    INFO)  echo 1 ;;
    WARN)  echo 2 ;;
    ERROR) echo 3 ;;
    *)     echo 1 ;;
  esac
}

_log_should_emit() {
  local level="$1"
  [[ $(_log_level_rank "${level}") -ge $(_log_level_rank "${FEDORA_LOG_LEVEL}") ]]
}

_log_timestamp() {
  date -Is
}

_log_format_line() {
  local level="$1"
  shift
  local line
  line="[$(_log_timestamp)] [${level}]"
  [[ -n "${FEDORA_LOG_SESSION_ID}" ]] && line+=" [${FEDORA_LOG_SESSION_ID}]"
  [[ -n "${FEDORA_LOG_SCRIPT_NAME}" ]] && line+=" [${FEDORA_LOG_SCRIPT_NAME}]"
  line+=" $*"
  printf '%s\n' "${line}"
}

# Core emit: stdout when tee active (captured), else append to LOG_FILE, else stdout.
_log_emit() {
  local level="$1"
  shift
  _log_should_emit "${level}" || return 0
  local line
  line="$(_log_format_line "${level}" "$@")"
  if [[ "${FEDORA_LOG_TEE_ACTIVE}" -eq 1 ]]; then
    printf '%s\n' "${line}"
  elif [[ -n "${LOG_FILE:-}" ]]; then
    printf '%s\n' "${line}" >> "${LOG_FILE}"
  else
    printf '%s\n' "${line}"
  fi
}

# ---------- structured writers ----------
log_debug() { _log_emit DEBUG "$@"; }
log_info()  { _log_emit INFO  "$@"; }
log_warn()  { _log_emit WARN  "$@"; }
log_error() { _log_emit ERROR "$@"; }

log_step() {
  local current="$1"
  local total="$2"
  shift 2
  _log_emit INFO "[${current}/${total}] $*"
}

log_cmd() {
  local rc=0
  log_info "CMD: $*"
  "$@" || rc=$?
  if [[ "${rc}" -eq 0 ]]; then
    log_info "CMD OK (exit 0): $*"
  else
    log_error "CMD FAIL (exit ${rc}): $*"
  fi
  return "${rc}"
}

log_engine_status() {
  cat <<EOF
Logging engine status:
  LOG_FILE           : ${LOG_FILE:-<unset>}
  LOG_DIR            : ${LOG_DIR:-<unset>}
  FEDORA_LOG_LEVEL   : ${FEDORA_LOG_LEVEL}
  FEDORA_LOG_SESSION : ${FEDORA_LOG_SESSION_ID:-<none>}
  FEDORA_LOG_TEE     : ${FEDORA_LOG_TEE_ACTIVE}
  FEDORA_LOG_SCRIPT  : ${FEDORA_LOG_SCRIPT_NAME:-<none>}
  FEDORA_LOG_ROTATE  : ${FEDORA_LOG_ROTATE_MB} MB (0=off)
EOF
}

# ---------- paths ----------
log_dir() {
  printf '%s\n' "$(fedora_toolkit_root)/logs"
}

log_archive_dir() {
  printf '%s\n' "$(log_dir)/archive"
}

log_backup_dir() {
  printf '%s\n' "$(log_dir)/backups"
}

log_file_path() {
  local name="$1"
  printf '%s/%s\n' "$(log_dir)" "${name}"
}

ensure_log_dir() {
  local owner_user owner_group
  LOG_DIR="$(log_dir)"
  owner_user="$(real_user)"
  owner_group="$(id -gn "${owner_user}" 2>/dev/null || echo "${owner_user}")"

  mkdir -p "${LOG_DIR}" "$(log_archive_dir)" "$(log_backup_dir)"
  chmod 0755 "${LOG_DIR}" "$(log_archive_dir)" "$(log_backup_dir)" 2>/dev/null || true
  if [[ "${EUID}" -eq 0 ]]; then
    chown "${owner_user}:${owner_group}" "${LOG_DIR}" 2>/dev/null || true
    chown "${owner_user}:${owner_group}" "$(log_archive_dir)" 2>/dev/null || true
    chown "${owner_user}:${owner_group}" "$(log_backup_dir)" 2>/dev/null || true
  fi
}

ensure_log_file() {
  local log_name="$1"
  local owner_user owner_group

  ensure_log_dir
  LOG_FILE="${LOG_DIR}/${log_name}"
  owner_user="$(real_user)"
  owner_group="$(id -gn "${owner_user}" 2>/dev/null || echo "${owner_user}")"

  touch "${LOG_FILE}"
  chmod 0644 "${LOG_FILE}" || true
  if [[ "${EUID}" -eq 0 ]]; then
    chown "${owner_user}:${owner_group}" "${LOG_FILE}" 2>/dev/null || true
  fi
}

fix_script_log_ownership() {
  [[ -n "${LOG_FILE:-}" ]] || return 0
  local owner_user owner_group
  owner_user="$(real_user)"
  owner_group="$(id -gn "${owner_user}" 2>/dev/null || echo "${owner_user}")"
  if [[ "${EUID}" -eq 0 ]]; then
    chown "${owner_user}:${owner_group}" "${LOG_FILE}" 2>/dev/null || true
    chown "${owner_user}:${owner_group}" "$(dirname "${LOG_FILE}")" 2>/dev/null || true
  fi
  chmod 0644 "${LOG_FILE}" 2>/dev/null || true
  chmod 0755 "$(dirname "${LOG_FILE}")" 2>/dev/null || true
}

# ---------- session lifecycle ----------
log_session_banner() {
  local title="${1:-Fedora toolkit script}"
  local script_name="${2:-${0##*/}}"

  if [[ -t 1 ]]; then
    common_init_colors
    theme_plain_banner "${title}"
    theme_meta_line "SESSION START : $(_log_timestamp)"
    theme_meta_line "Session-ID    : ${FEDORA_LOG_SESSION_ID}"
    theme_meta_line "Script        : ${script_name}"
    theme_meta_line "Host          : $(hostname)"
    theme_meta_line "Invoker       : $(real_user)"
    theme_meta_line "Log level     : ${FEDORA_LOG_LEVEL}"
    theme_meta_line "Log file      : ${LOG_FILE}"
    echo
    log_info "Session started"
    return 0
  fi

  echo "============================================================"
  echo "${title}"
  echo "SESSION START : $(_log_timestamp)"
  echo "Session-ID    : ${FEDORA_LOG_SESSION_ID}"
  echo "Script        : ${script_name}"
  echo "Host          : $(hostname)"
  echo "Invoker       : $(real_user)"
  echo "Log level     : ${FEDORA_LOG_LEVEL}"
  echo "Log file      : ${LOG_FILE}"
  echo "============================================================"
  echo
  log_info "Session started"
}

log_session_footer() {
  local rc="${1:-0}"

  if [[ "${rc}" -eq 0 ]]; then
    log_info "Session finished successfully"
  else
    log_error "Session failed with exit code ${rc}"
  fi

  echo
  if [[ -t 1 ]]; then
    common_init_colors
    theme_rule '─'
    if [[ "${rc}" -eq 0 ]]; then
      ok "Status: SUCCESS"
    else
      err "Status: FAILED (exit code: ${rc})"
    fi
    theme_meta_line "SESSION END   : $(_log_timestamp)"
    theme_meta_line "Session-ID    : ${FEDORA_LOG_SESSION_ID}"
    theme_meta_line "Log file      : ${LOG_FILE}"
    theme_rule '─'
    return 0
  fi

  echo "============================================================"
  if [[ "${rc}" -eq 0 ]]; then
    echo "Status        : SUCCESS"
  else
    echo "Status        : FAILED (exit code: ${rc})"
  fi
  echo "SESSION END   : $(_log_timestamp)"
  echo "Session-ID    : ${FEDORA_LOG_SESSION_ID}"
  echo "Log file      : ${LOG_FILE}"
  echo "============================================================"
}

logging_start_tee() {
  FEDORA_LOG_TEE_ACTIVE=1
  exec > >(tee -a "${LOG_FILE}") 2>&1
}

setup_script_logging() {
  local log_name="${1:?log name required}"
  local script_name="${2:-${0##*/}}"
  local title="${3:-Fedora toolkit script}"

  FEDORA_LOG_SCRIPT_NAME="${script_name}"
  FEDORA_LOG_SESSION_ID="$(date +%Y%m%d-%H%M%S)-$$"

  if [[ "${FEDORA_LOG_ROTATE_MB}" =~ ^[0-9]+$ ]] && (( FEDORA_LOG_ROTATE_MB > 0 )); then
    log_rotate_if_large "${log_name}" "${FEDORA_LOG_ROTATE_MB}" || true
  fi

  ensure_log_file "${log_name}"
  logging_start_tee
  log_session_banner "${title}" "${script_name}"
}

logging_install_exit_trap() {
  trap '_fedora_logging_exit_trap $?' EXIT
}

_fedora_logging_exit_trap() {
  local rc=$?
  if declare -F errors_run_cleanups >/dev/null 2>&1; then
    errors_run_cleanups || true
  fi
  FEDORA_LOG_TEE_ACTIVE=0
  fix_script_log_ownership
  log_session_footer "${rc}"
  exit "${rc}"
}

# Full engine start: tee + session banner + EXIT trap.
init_script_logging() {
  local log_name="$1"
  local script_name="${2:-${0##*/}}"
  local title="${3:-Fedora toolkit script}"

  setup_script_logging "${log_name}" "${script_name}" "${title}"
  logging_install_exit_trap
}

# Attach logging to an existing script without replacing other traps (manual footer).
log_engine_open() {
  local log_name="$1"
  local script_name="${2:-${0##*/}}"
  local title="${3:-Fedora toolkit script}"

  setup_script_logging "${log_name}" "${script_name}" "${title}"
}

log_engine_close() {
  local rc="${1:-0}"
  FEDORA_LOG_TEE_ACTIVE=0
  fix_script_log_ownership
  log_session_footer "${rc}"
}

# ---------- read / maintenance / archive ----------
log_file_size_mb() {
  local path="$1"
  [[ -f "${path}" ]] || { echo 0; return 0; }
  echo $(( $(stat -c '%s' "${path}" 2>/dev/null || echo 0) / 1048576 ))
}

log_archive_file() {
  local log_name="${1:?log name}"
  local path archive_dir base dest
  path="$(log_file_path "${log_name}")"
  [[ -f "${path}" ]] || { warn "Nothing to archive: ${path}"; return 0; }

  archive_dir="$(log_archive_dir)"
  base="${log_name%.log}"
  dest="${archive_dir}/${base}-$(date +%Y%m%d-%H%M%S).log"

  cp -a "${path}" "${dest}"
  fix_script_log_ownership
  ok "Archived to ${dest}"
  printf '%s\n' "${dest}"
}

log_rotate_if_large() {
  local log_name="${1:?log name}"
  local max_mb="${2:-10}"
  local path size_mb
  path="$(log_file_path "${log_name}")"
  [[ -f "${path}" ]] || return 0

  size_mb="$(log_file_size_mb "${path}")"
  if (( size_mb >= max_mb )); then
    echo "[logging] Rotating ${log_name} (${size_mb}MB >= ${max_mb}MB)" >&2
    log_archive_file "${log_name}"
    : > "${path}"
    fix_script_log_ownership
    ok "Rotated ${log_name} (was ${size_mb}MB)"
  fi
}

log_truncate_file() {
  local log_name="${1:?log name}"
  local path
  path="$(log_file_path "${log_name}")"

  if [[ ! -f "${path}" ]]; then
    warn "Nothing to truncate: ${path}"
    return 0
  fi

  : > "${path}"
  fix_script_log_ownership
  ok "Truncated ${path}"
}

log_list_files() {
  local dir archive
  dir="$(log_dir)"
  archive="$(log_archive_dir)"
  ensure_log_dir

  echo "Operational logs (${dir}):"
  shopt -s nullglob
  local f
  for f in "${dir}"/*.log; do
    ls -lh "${f}"
  done
  shopt -u nullglob

  echo
  echo "Archive (${archive}):"
  ls -lh "${archive}" 2>/dev/null | tail -n +2 | head -n 15 || echo "  (empty)"

  echo
  echo "Backups ($(log_backup_dir)):"
  ls -lh "$(log_backup_dir)" 2>/dev/null | tail -n +2 | head -n 10 || echo "  (empty)"
}

log_show_sessions() {
  local log_name="${1:-${FEDORA_LOG_SYSTEM_UPDATE}}"
  local path
  path="$(log_file_path "${log_name}")"

  if [[ ! -f "${path}" ]]; then
    err "Log not found: ${path}"
    return 1
  fi

  echo "Sessions in ${path}:"
  grep -nE '^(SESSION START|SESSION END|Session-ID    |Status        )' "${path}" \
    || echo "  (no session markers — log may predate logging v0.2)"
}

log_summary() {
  local log_name="${1:-${FEDORA_LOG_SYSTEM_UPDATE}}"
  local path
  path="$(log_file_path "${log_name}")"

  if [[ ! -f "${path}" ]]; then
    err "Log not found: ${path}"
    return 1
  fi

  common_init_colors

  local starts success fail errors warns size_mb
  starts=$(grep -c 'SESSION START' "${path}" 2>/dev/null || true); starts=${starts:-0}
  success=$(grep -c 'Status        : SUCCESS' "${path}" 2>/dev/null || true); success=${success:-0}
  fail=$(grep -c 'Status        : FAILED' "${path}" 2>/dev/null || true); fail=${fail:-0}
  errors=$(grep -cE '\[ERROR\]|^ERROR:' "${path}" 2>/dev/null || true); errors=${errors:-0}
  warns=$(grep -cE '\[WARN\]|^WARN:' "${path}" 2>/dev/null || true); warns=${warns:-0}
  size_mb="$(log_file_size_mb "${path}")"
  local size_human="${size_mb} MB"
  if (( size_mb == 0 )); then
    local bytes
    bytes=$(stat -c '%s' "${path}" 2>/dev/null || echo 0)
    if (( bytes >= 1024 )); then
      size_human="$(( bytes / 1024 )) KB"
    else
      size_human="${bytes} B"
    fi
  fi

  if theme_use_color; then
    theme_lane_banner "Log summary" system
    theme_meta_line "${path}"
    theme_rule '─'
    theme_kv "Size" "${size_human}"
    theme_kv "Sessions" "${starts} started"
    theme_kv "Success" "${success}"
    theme_kv "Failed" "${fail}"
    theme_kv "Errors" "${errors} lines"
    theme_kv "Warnings" "${warns} lines"
    theme_kv "Modified" "$(stat -c '%y' "${path}" 2>/dev/null | cut -d. -f1 || echo unknown)"
  else
    echo "Log summary: ${path}"
    echo "  Size           : ${size_human}"
    echo "  Sessions start : ${starts}"
    echo "  Success        : ${success}"
    echo "  Failed         : ${fail}"
    echo "  [ERROR] lines  : ${errors}"
    echo "  [WARN] lines   : ${warns}"
    echo "  Last modified  : $(stat -c '%y' "${path}" 2>/dev/null | cut -d. -f1 || echo unknown)"
  fi
}

log_grep_issues() {
  local log_name="${1:-${FEDORA_LOG_SYSTEM_UPDATE}}"
  local lines="${2:-80}"
  local path
  path="$(log_file_path "${log_name}")"

  if [[ ! -f "${path}" ]]; then
    err "Log not found: ${path}"
    return 1
  fi

  echo "Issues in ${path} (last ${lines} matches):"
  grep -nE \
    -e '\[ERROR\]' \
    -e '\[WARN\]' \
    -e 'Status        : FAILED' \
    -e '^ERROR:' \
    -e '^\[ERROR\]' \
    -e 'CMD FAIL' \
    "${path}" 2>/dev/null | tail -n "${lines}" || echo "  (no issues found)"
}

log_tail_file() {
  local log_name="${1:?log name}"
  local lines="${2:-50}"
  local follow="${3:-0}"
  local path
  path="$(log_file_path "${log_name}")"

  if [[ ! -f "${path}" ]]; then
    err "Log not found: ${path}"
    return 1
  fi

  echo "== ${path} (last ${lines} lines) =="
  if [[ "${follow}" -eq 1 ]]; then
    tail -n "${lines}" -f "${path}"
  else
    tail -n "${lines}" "${path}"
  fi
}

# Legacy view_logs.sh flag mapping → log_engine.sh (deprecated entry point)
logging_view_logs_legacy() {
  local engine="${1:?log_engine path required}"
  shift

  local lines=50
  local log_name="${FEDORA_LOG_SYSTEM_UPDATE}"
  local mode='tail'
  local follow=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --list|-l) mode='list'; shift ;;
      --tail|-n)
        mode='tail'
        if [[ -n "${2:-}" && "${2}" =~ ^[0-9]+$ ]]; then
          lines="$2"
          shift 2
        else
          shift
        fi
        ;;
      --file|-f)
        log_name="${2:?missing filename}"
        shift 2
        ;;
      --sessions|-s) mode='sessions'; shift ;;
      --summary) mode='summary'; shift ;;
      --errors|--issues) mode='issues'; shift ;;
      --follow|-F) follow=1; mode='tail'; shift ;;
      --help|-h)
        exec bash "${engine}" help
        ;;
      *)
        err "Unknown option: $1 (try: ./system/log_engine.sh help)"
        return 2
        ;;
    esac
  done

  case "${mode}" in
    list) exec bash "${engine}" list ;;
    sessions) exec bash "${engine}" sessions --file "${log_name}" ;;
    summary) exec bash "${engine}" summary --file "${log_name}" ;;
    issues) exec bash "${engine}" issues --file "${log_name}" --lines "${lines}" ;;
    tail)
      if [[ "${follow}" -eq 1 ]]; then
        exec bash "${engine}" follow --file "${log_name}" --lines "${lines}"
      else
        exec bash "${engine}" tail --file "${log_name}" --lines "${lines}"
      fi
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
