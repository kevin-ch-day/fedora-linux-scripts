#!/usr/bin/env bash
# lib/system_state.sh — mounts, SELinux, tools, and runtime capabilities
# Version: 0.1.0
#
# Read-only system posture helpers. Source after lib/common.sh.

if [[ -n "${FEDORA_SYSTEM_STATE_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_SYSTEM_STATE_SH_LOADED=1

_SYS_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_SYS_LIB_DIR}/common.sh"
# shellcheck source=health.sh
source "${_SYS_LIB_DIR}/health.sh"
# shellcheck source=logging.sh
source "${_SYS_LIB_DIR}/logging.sh"
# shellcheck source=services.sh
source "${_SYS_LIB_DIR}/services.sh"

# ---------- SELinux ----------
system_state_selinux_mode() {
  getenforce 2>/dev/null | tr '[:upper:]' '[:lower:]' || printf 'unknown\n'
}

system_state_selinux_enforcing() {
  [[ "$(system_state_selinux_mode)" == "enforcing" ]]
}

# ---------- mounts / storage ----------
system_state_mount_line() {
  local mount="$1"
  findmnt -no SOURCE,FSTYPE,OPTIONS "${mount}" 2>/dev/null || true
}

system_state_is_mounted() {
  findmnt -n "$1" >/dev/null 2>&1
}

system_state_data_mounted() {
  system_state_is_mounted /data
}

system_state_data_writable() {
  system_state_data_mounted && [[ -d /data && -w /data ]]
}

# Prefer /data/logs when mounted; else toolkit logs/
system_state_log_root() {
  local sub="${1:-}"
  if system_state_data_writable; then
    if [[ -n "${sub}" ]]; then
      printf '/data/logs/%s\n' "${sub}"
    else
      printf '/data/logs\n'
    fi
    return 0
  fi
  if [[ -n "${sub}" ]]; then
    printf '%s/%s\n' "$(log_dir)" "${sub}"
  else
    log_dir
  fi
}

system_state_key_mounts_summary() {
  local m
  for m in / /home /boot /boot/efi /data /var; do
    if system_state_is_mounted "${m}"; then
      printf '%s=%s\n' "${m}" "$(system_state_mount_line "${m}")"
    else
      printf '%s=(not mounted)\n' "${m}"
    fi
  done
}

# ---------- privilege / tooling ----------
system_state_sudo_available() {
  have sudo
}

system_state_sudo_passwordless() {
  system_state_sudo_available && sudo -n true 2>/dev/null
}

system_state_running_as_root() {
  [[ "${EUID}" -eq 0 ]]
}

system_state_invoker_is_root() {
  [[ "$(real_user)" == root ]]
}

# Space-separated list of tools present on PATH
system_state_tools_present() {
  local -a want=(dnf rpm systemctl firewall-cmd nmcli ss curl git podman docker)
  local t out=()
  for t in "${want[@]}"; do
    have "${t}" && out+=("${t}")
  done
  printf '%s\n' "${out[*]}"
}

system_state_tool_missing() {
  local t want="$1"
  have "${want}" && return 1
  printf '%s\n' "${want}"
  return 0
}

# ---------- session (GUI vs remote) — alias layer over users.sh when loaded ----------
system_state_session_kind() {
  if [[ -n "${FEDORA_USERS_SH_LOADED:-}" ]]; then
    users_session_kind
    return 0
  fi
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    printf 'ssh\n'
  elif [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
    printf 'local\n'
  else
    printf 'unknown\n'
  fi
}

system_state_is_fedora() {
  [[ -r /etc/fedora-release ]] && return 0
  [[ -r /etc/os-release ]] && grep -qiE '^ID=fedora' /etc/os-release 2>/dev/null
}

system_state_os_label() {
  local pretty id version
  pretty="$(health_os_pretty 2>/dev/null | head -n 1 | tr -d '\r')"
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-unknown}"
    version="${VERSION_ID:-}"
    if [[ -n "${version}" ]]; then
      printf '%s (%s %s)\n' "${pretty:-${id}}" "${id}" "${version}"
      return 0
    fi
  fi
  [[ -n "${pretty}" ]] && printf '%s\n' "${pretty}" && return 0
  cat /etc/fedora-release 2>/dev/null || printf 'unknown\n'
}

system_state_failed_units_count() {
  health_failed_systemd_units_count
}

system_state_service_active() {
  service_unit_active "$1"
}

system_state_service_enabled() {
  service_unit_enabled "$1"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
