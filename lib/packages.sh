#!/usr/bin/env bash
# lib/packages.sh — shared Fedora package-management helpers
# Version: 0.2.7
#
# Source from task scripts (after or via common.sh):
#   _dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck source=../lib/packages.sh
#   source "${_dir}/../lib/packages.sh"
#
# Do not execute directly.

if [[ -n "${FEDORA_PACKAGES_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_PACKAGES_SH_LOADED=1

_PKG_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_PKG_LIB_DIR}/common.sh"

# ---------- output (logging-aware when lib/logging.sh is active) ----------
pkg_emit() {
  if [[ "${FEDORA_LOG_TEE_ACTIVE:-0}" -eq 1 ]] && declare -F log_info >/dev/null 2>&1; then
    log_info "$*"
  else
    printf '%s\n' "$*"
  fi
}

# Fix .repo permissions so non-root dnf check works after sudo updates (e.g. virtualbox.repo).
packages_fix_repo_permissions() {
  [[ "${EUID}" -eq 0 ]] || return 0
  local f invoker fixed=0
  invoker="${SUDO_USER:-${FEDORA_REAL_USER:-}}"
  shopt -s nullglob
  for f in /etc/yum.repos.d/*.repo; do
    [[ -f "${f}" ]] || continue
    if [[ -n "${invoker}" && "${invoker}" != root ]] \
       && ! sudo -u "${invoker}" test -r "${f}" 2>/dev/null; then
      if chmod 644 "${f}" 2>/dev/null; then
        pkg_emit "Fixed repo permissions (644): ${f}"
        fixed=1
      else
        warn "Could not fix repo permissions: ${f}"
      fi
    elif [[ ! -r "${f}" ]]; then
      chmod 644 "${f}" 2>/dev/null && fixed=1 || warn "Could not fix repo permissions: ${f}"
    fi
  done
  shopt -u nullglob
  (( fixed )) || return 0
}

# ---------- dnf core ----------
require_dnf() {
  cmd_available dnf || die "dnf not found."
}

_pkg_fixup_repo_permissions_after_dnf() {
  if [[ "${EUID}" -eq 0 ]]; then
    packages_fix_repo_permissions
    return 0
  fi
  # Avoid a second password prompt after user-level sudo dnf.
  if sudo -n true 2>/dev/null; then
    sudo -n bash -c "source '${_PKG_LIB_DIR}/packages.sh'; packages_fix_repo_permissions" 2>/dev/null || true
  fi
}

_dnf_run() {
  local ctx="$1"
  shift
  errors_dnf_hint
  if [[ "${EUID}" -eq 0 ]]; then
    run_or_die "${ctx}" dnf_yes "$@"
  else
    run_or_die "${ctx}" sudo dnf -y "$@"
  fi
  errors_clear_hint
  _pkg_fixup_repo_permissions_after_dnf
}

# Public alias for task scripts (group install, etc.).
pkg_dnf_run() {
  _dnf_run "$@"
}

dnf_yes() {
  dnf -y "$@"
}

dnf_installed() {
  # Prefer rpm (fast, works when dnf repos are unreadable without sudo).
  if rpm -q "$1" >/dev/null 2>&1; then
    return 0
  fi
  if command -v timeout >/dev/null 2>&1; then
    timeout 8 dnf list installed "$1" >/dev/null 2>&1 && return 0
  else
    dnf list installed "$1" >/dev/null 2>&1 && return 0
  fi
  return 1
}

# True when the RPM is installed or a common binary path exists (sudo PATH-safe).
pkg_present() {
  local pkg="$1"
  local bin="${2:-${pkg}}"
  dnf_installed "${pkg}" && return 0
  pkg_binary_path "${bin}" >/dev/null 2>&1
}

pkg_binary_path() {
  cmd_binary_path "$1"
}

pkg_rpm_satisfied() {
  local pkg="$1"
  dnf_installed "${pkg}" && return 0
  rpm -q --whatprovides "${pkg}" >/dev/null 2>&1
}

# Install a package via dnf if not already installed.
pkg_install_if_missing() {
  local pkg="$1"
  if pkg_present "${pkg}"; then
    ok "${pkg} already installed"
    return 0
  fi
  info "Installing ${pkg}..."
  _dnf_run "Failed to install ${pkg}" install "${pkg}"
  if ! pkg_present "${pkg}"; then
    die "Installed ${pkg} but it is still not present (check package name or binary path)"
  fi
  ok "${pkg} installed"
}

# Install an RPM by package name only; do not require a same-named binary on PATH.
pkg_install_rpm_if_missing() {
  local pkg="$1"
  if pkg_rpm_satisfied "${pkg}"; then
    ok "${pkg} already installed"
    return 0
  fi
  info "Installing ${pkg}..."
  _dnf_run "Failed to install ${pkg}" install "${pkg}"
  if ! pkg_rpm_satisfied "${pkg}"; then
    die "Installed ${pkg} but no installed RPM now satisfies it"
  fi
  ok "${pkg} installed"
}

# Install package when available; skip quietly when repo lacks it.
pkg_install_optional() {
  local pkg="$1"
  if pkg_present "${pkg}"; then
    ok "${pkg} already installed"
    return 0
  fi
  if dnf -q list --available "${pkg}" >/dev/null 2>&1; then
    info "Installing ${pkg}..."
    _dnf_run "Failed to install ${pkg}" install "${pkg}" >/dev/null
    if pkg_present "${pkg}"; then
      ok "${pkg} installed"
    else
      warn "Installed ${pkg} but presence check failed (binary may use a different name)"
    fi
  else
    warn "Skipping (not available): ${pkg}"
  fi
}

# Install a dnf package if a command is missing from PATH (sudo/PATH-safe).
pkg_install_cmd_if_missing() {
  local cmd="$1"
  local pkg="${2:-$1}"
  if pkg_present "${pkg}" "${cmd}"; then
    ok "${cmd} already available (${pkg} installed)"
    return 0
  fi
  require_dnf
  info "Installing ${pkg} (dnf) for command ${cmd}..."
  _dnf_run "Failed to install ${pkg} for command ${cmd}" install "${pkg}" >/dev/null
  if ! pkg_present "${pkg}" "${cmd}"; then
    die "Installed ${pkg} but ${cmd} is still not available (check PATH or package contents)"
  fi
  ok "${pkg} installed"
}

# Install multiple packages; skip installed, warn on unavailable repo packages.
# Unavailable names are appended to the array named by the first argument.
pkg_install_batch_if_available() {
  local missing_array_name="$1"
  shift
  local -n _missing_ref="${missing_array_name}"
  local pkgs=("$@")
  local to_install=()
  local p

  for p in "${pkgs[@]}"; do
    if pkg_present "${p}"; then
      ok "${p} already installed"
      continue
    fi
    if dnf -q list --available "${p}" >/dev/null 2>&1; then
      to_install+=("${p}")
    else
      warn "Not available in enabled repos: ${p}"
      _missing_ref+=("${p}")
    fi
  done

  if ((${#to_install[@]} > 0)); then
    info "Installing: ${to_install[*]}"
    _dnf_run "Batch install failed" install "${to_install[@]}" >/dev/null
    for p in "${to_install[@]}"; do ok "${p} installed"; done
  fi
}

dnf_upgrade_refresh() {
  info "Refreshing package metadata and upgrading..."
  if [[ "${EUID}" -eq 0 ]]; then
    dnf_yes upgrade --refresh
  else
    sudo dnf upgrade --refresh -y
  fi
  ok "System packages upgraded"
}

wait_for_dnf_lock() {
  local timeout=600
  local start now waited=0
  pkg_emit "[lock] Waiting for dnf/rpm/PackageKit locks (max ${timeout}s)..."
  start="$(date +%s)"

  while true; do
    if ! pgrep -x dnf >/dev/null 2>&1 \
       && ! pgrep -x rpm >/dev/null 2>&1 \
       && ! pgrep -x PackageKit >/dev/null 2>&1; then
      if (( waited > 0 )); then
        pkg_emit "[lock] Package manager idle after ${waited}s."
      else
        pkg_emit "[lock] No active package manager detected."
      fi
      return 0
    fi
    now="$(date +%s)"
    waited=$(( now - start ))
    if (( waited >= timeout )); then
      die_with_hint \
        "Timed out waiting for package manager locks." \
        "Close Software / PackageKit, wait for other dnf sessions, then retry."
    fi
    if (( waited > 0 && waited % 15 == 0 )); then
      pkg_emit "[lock] Still waiting (${waited}s)..."
    fi
    sleep 3
  done
}

# ---------- dnf operations ----------
dnf_makecache_refresh() {
  dnf_yes makecache --refresh
}

dnf_show_updates() {
  local rc=0
  set +e
  dnf -q check-update
  rc=$?
  set -e
  return "${rc}"
}

dnf_upgrade() {
  dnf_yes upgrade
}

dnf_distro_sync() {
  dnf_yes distro-sync
}

dnf_autoremove() {
  dnf_yes autoremove
}

dnf_clean_all() {
  dnf_yes clean all
}

dnf_check() {
  dnf_yes check
}

packages_preflight() {
  require_dnf
  errors_check_dnf_repos
  packages_fix_repo_permissions
  pkg_emit "[preflight] Fedora release: $(cat /etc/fedora-release 2>/dev/null || echo "unknown")"
  pkg_emit "[preflight] Kernel         : $(uname -r)"
  printf '\n'
}

# ---------- rpm / kernel ----------
rpm_installed_kernels() {
  have rpm || return 1
  rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V || true
}

kernel_prune_keep3() {
  have rpm || { pkg_emit "Skipping kernel prune (rpm not available)."; return 0; }

  local kernels=()
  mapfile -t kernels < <(rpm_installed_kernels || true)

  if (( ${#kernels[@]} <= 3 )); then
    pkg_emit "No old kernels to remove (installed: ${#kernels[@]})."
    return 0
  fi

  local remove_count=$(( ${#kernels[@]} - 3 ))
  local remove_pkgs=()
  local i
  for ((i=0; i<remove_count; i++)); do
    remove_pkgs+=( "kernel-${kernels[$i]}" )
  done

  pkg_emit "Removing old kernels (keeping latest 3):"
  printf '  %s\n' "${remove_pkgs[@]}"
  dnf_yes remove "${remove_pkgs[@]}"
}

rpm_verify_report() {
  local max_lines="${1:-200}"
  local timeout_sec="${2:-180}"
  have rpm || { pkg_emit "Skipping rpm verify (rpm not available)."; return 0; }

  pkg_emit "[rpm -Va] Verifying installed packages (timeout ${timeout_sec}s, up to ${max_lines} lines)..."
  local out filtered rc=0
  if have timeout; then
    out="$(timeout "${timeout_sec}" rpm -Va 2>/dev/null)" || rc=$?
    if (( rc == 124 )); then
      warn "rpm -Va timed out after ${timeout_sec}s — partial verify only"
      rc=0
    fi
  else
    out="$(rpm -Va 2>/dev/null || true)"
  fi

  if [[ -z "${out}" ]]; then
    pkg_emit "No verification deltas detected."
    return 0
  fi

  filtered="$(printf '%s\n' "${out}" | grep -vE '^missing\s+/(run|var/run)/' || true)"

  if [[ -z "${filtered}" ]]; then
    pkg_emit "Only runtime-path missing entries detected (ignored)."
    return 0
  fi

  echo
  pkg_emit "Config file changes (usually expected if you edited configs):"
  printf '%s\n' "${filtered}" | grep -E '^\S+\s+c\s+/' | head -n "${max_lines}" || echo "  (none)"

  echo
  pkg_emit "Other verification deltas (review):"
  printf '%s\n' "${filtered}" | grep -vE '^\S+\s+c\s+/' | head -n "${max_lines}" || echo "  (none)"
}

needs_reboot_check() {
  pkg_emit "Reboot check:"

  local running newest
  running="$(uname -r)"
  newest=""
  if have rpm; then
    newest="$(rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V | tail -n 1 || true)"
  fi

  if [[ -n "${newest}" ]] && [[ "${running}" != "${newest}" ]]; then
    pkg_emit "  Reboot recommended: newest installed kernel is ${newest}, running is ${running}."
    return 0
  fi

  if have needs-restarting; then
    if needs-restarting -r >/dev/null 2>&1; then
      pkg_emit "  No reboot required."
    else
      pkg_emit "  Reboot recommended (per needs-restarting)."
    fi
  else
    pkg_emit "  No reboot required based on kernel check."
    pkg_emit "  (Install dnf-plugins-core for needs-restarting accuracy on userland updates.)"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
