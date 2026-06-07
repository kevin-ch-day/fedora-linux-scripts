#!/usr/bin/env bash
# lib/packages.sh — shared Fedora package-management helpers
# Version: 0.2.3
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

# ---------- dnf core ----------
require_dnf() {
  have dnf || die "dnf not found."
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
}

# Public alias for task scripts (group install, etc.).
pkg_dnf_run() {
  _dnf_run "$@"
}

dnf_yes() {
  dnf -y "$@"
}

dnf_installed() {
  dnf list installed "$1" >/dev/null 2>&1
}

# Install a package via dnf if not already installed.
pkg_install_if_missing() {
  local pkg="$1"
  if dnf_installed "${pkg}"; then
    ok "${pkg} already installed"
    return 0
  fi
  info "Installing ${pkg}..."
  _dnf_run "Failed to install ${pkg}" install "${pkg}"
  ok "${pkg} installed"
}

# Install package when available; skip quietly when repo lacks it.
pkg_install_optional() {
  local pkg="$1"
  if dnf_installed "${pkg}"; then
    ok "${pkg} already installed"
    return 0
  fi
  if dnf -q list --available "${pkg}" >/dev/null 2>&1; then
    info "Installing ${pkg}..."
    _dnf_run "Failed to install ${pkg}" install "${pkg}" >/dev/null
    ok "${pkg} installed"
  else
    warn "Skipping (not available): ${pkg}"
  fi
}

# Install a dnf package if a command is missing from PATH.
pkg_install_cmd_if_missing() {
  local cmd="$1"
  local pkg="${2:-$1}"
  if have "${cmd}"; then
    ok "${cmd} already available"
    return 0
  fi
  require_dnf
  info "Installing ${pkg} (dnf) for command ${cmd}..."
  _dnf_run "Failed to install ${pkg} for command ${cmd}" install "${pkg}" >/dev/null
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
    if dnf_installed "${p}"; then
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
  local start now
  echo "[lock] Waiting for dnf/rpm/PackageKit locks (max ${timeout}s)..."
  start="$(date +%s)"

  while true; do
    if ! pgrep -x dnf >/dev/null 2>&1 \
       && ! pgrep -x rpm >/dev/null 2>&1 \
       && ! pgrep -x PackageKit >/dev/null 2>&1; then
      echo "[lock] No active package manager detected."
      return 0
    fi
    now="$(date +%s)"
    if (( now - start >= timeout )); then
      die_with_hint \
        "Timed out waiting for package manager locks." \
        "Close Software / PackageKit, wait for other dnf sessions, then retry."
    fi
    sleep 3
  done
}

# ---------- dnf operations ----------
dnf_makecache_refresh() {
  dnf_yes makecache --refresh
}

dnf_show_updates() {
  dnf -q check-update || true
}

dnf_upgrade() {
  dnf_yes upgrade
}

dnf_distro_sync() {
  dnf_yes distro-sync || true
}

dnf_autoremove() {
  dnf_yes autoremove
}

dnf_clean_all() {
  dnf_yes clean all
}

dnf_check() {
  dnf_yes check || true
}

packages_preflight() {
  require_dnf
  errors_check_dnf_repos
  echo "[preflight] Fedora release: $(cat /etc/fedora-release 2>/dev/null || echo "unknown")"
  echo "[preflight] Kernel         : $(uname -r)"
  echo
}

# ---------- rpm / kernel ----------
rpm_installed_kernels() {
  have rpm || return 1
  rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V || true
}

kernel_prune_keep3() {
  have rpm || { echo "Skipping kernel prune (rpm not available)."; return 0; }

  local kernels=()
  mapfile -t kernels < <(rpm_installed_kernels || true)

  if (( ${#kernels[@]} <= 3 )); then
    echo "No old kernels to remove (installed: ${#kernels[@]})."
    return 0
  fi

  local remove_count=$(( ${#kernels[@]} - 3 ))
  local remove_pkgs=()
  local i
  for ((i=0; i<remove_count; i++)); do
    remove_pkgs+=( "kernel-${kernels[$i]}" )
  done

  echo "Removing old kernels (keeping latest 3):"
  printf '  %s\n' "${remove_pkgs[@]}"
  dnf_yes remove "${remove_pkgs[@]}" || true
}

rpm_verify_report() {
  have rpm || { echo "Skipping rpm verify (rpm not available)."; return 0; }

  echo "[rpm -Va] Verifying installed packages (filtered)..."
  local out filtered
  out="$(rpm -Va 2>/dev/null || true)"

  if [[ -z "${out}" ]]; then
    echo "No verification deltas detected."
    return 0
  fi

  # Ignore runtime path missing noise
  filtered="$(printf '%s\n' "${out}" | grep -vE '^missing\s+/(run|var/run)/' || true)"

  if [[ -z "${filtered}" ]]; then
    echo "Only runtime-path missing entries detected (ignored)."
    return 0
  fi

  echo
  echo "Config file changes (usually expected if you edited configs):"
  printf '%s\n' "${filtered}" | grep -E '^\S+\s+c\s+/' || echo "  (none)"

  echo
  echo "Other verification deltas (review):"
  printf '%s\n' "${filtered}" | grep -vE '^\S+\s+c\s+/' || echo "  (none)"
}

needs_reboot_check() {
  echo "Reboot check:"

  local running newest
  running="$(uname -r)"
  newest=""
  if have rpm; then
    newest="$(rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V | tail -n 1 || true)"
  fi

  if [[ -n "${newest}" ]] && [[ "${running}" != "${newest}" ]]; then
    echo "  Reboot recommended: newest installed kernel is ${newest}, running is ${running}."
    return 0
  fi

  if have needs-restarting; then
    if needs-restarting -r >/dev/null 2>&1; then
      echo "  No reboot required."
    else
      echo "  Reboot recommended (per needs-restarting)."
    fi
  else
    echo "  No reboot required based on kernel check."
    echo "  (Install dnf-plugins-core for needs-restarting accuracy on userland updates.)"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
