#!/usr/bin/env bash
# lib/host_context.sh — unified host awareness for audits and smart scripts
# Version: 0.2.0
#
# Aggregates users, network, and system state into one read-only context layer.
# Source after lib/common.sh (pulls users, network, system_state).

if [[ -n "${FEDORA_HOST_CONTEXT_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_HOST_CONTEXT_SH_LOADED=1

_CTX_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_CTX_LIB_DIR}/common.sh"
# shellcheck source=health.sh
source "${_CTX_LIB_DIR}/health.sh"
# shellcheck source=logging.sh
source "${_CTX_LIB_DIR}/logging.sh"
# shellcheck source=theme.sh
source "${_CTX_LIB_DIR}/theme.sh"
# shellcheck source=users.sh
source "${_CTX_LIB_DIR}/users.sh"
# shellcheck source=network.sh
source "${_CTX_LIB_DIR}/network.sh"
# shellcheck source=system_state.sh
source "${_CTX_LIB_DIR}/system_state.sh"

# ---------- profile / intent ----------
# FEDORA_HARDENING_PROFILE: research | desktop | workstation | auto
host_context_is_research_host() {
  local profile zone iface def
  profile="${FEDORA_HARDENING_PROFILE:-auto}"
  case "${profile}" in
    research) return 0 ;;
    desktop|workstation) return 1 ;;
  esac
  zone="$(network_firewall_strict_zone_name)"
  if network_firewall_zone_exists "${zone}"; then
    iface="$(network_firewall_interfaces_in_zone "${zone}" | head -n 1 | tr -d '[:space:]')"
    [[ -n "${iface}" ]] && return 0
  fi
  def="$(network_firewall_default_zone 2>/dev/null || true)"
  if [[ -n "${def}" ]] && network_firewall_zone_is_strict "${def}" 2>/dev/null; then
    return 0
  fi
  [[ "$(users_session_kind)" == "headless" ]]
}

host_context_research_label() {
  if host_context_is_research_host; then
    printf 'research (strict firewall / reduced listeners expected)\n'
  else
    printf 'desktop (workstation services OK — set FEDORA_HARDENING_PROFILE=research to enforce)\n'
  fi
}

host_context_host_slug() {
  network_host_slug
}

host_context_root() {
  if [[ -n "${FEDORA_HOST_CONTEXT_ROOT:-}" ]]; then
    printf '%s\n' "${FEDORA_HOST_CONTEXT_ROOT}"
    return 0
  fi
  system_state_log_root host_context
}

host_context_history_dir() {
  printf '%s/%s\n' "$(host_context_root)" "$(host_context_host_slug)"
}

host_context_snapshot_basename() {
  local stamp="$1"
  local slug
  slug="$(host_context_host_slug)"
  printf 'context_%s_%s.txt\n' "${slug}" "${stamp}"
}

host_context_save_snapshot() {
  local stamp="${1:-$(date +%Y%m%d_%H%M%S)}"
  local dir path
  dir="$(host_context_history_dir)"
  mkdir -p "${dir}"
  path="${dir}/$(host_context_snapshot_basename "${stamp}")"
  {
    echo "# Host context — $(health_hostname) — $(date -Iseconds)"
    host_context_snapshot
  } > "${path}"
  printf '%s\n' "${path}"
}

host_context_latest_snapshot_path() {
  local slug dir
  slug="$(host_context_host_slug)"
  dir="$(host_context_root)/${slug}"
  find "${dir}" -type f -name "context_${slug}_*.txt" 2>/dev/null | sort | tail -n 1
}

host_context_lookup() {
  local key="$1"
  host_context_snapshot | awk -F= -v k="${key}" '$1==k {print substr($0,index($0,"=")+1); exit}'
}

host_context_compare_snapshots() {
  local prev="$1"
  local key old new
  declare -A curr=()

  if [[ ! -f "${prev}" ]]; then
    info "No previous context snapshot to compare"
    return 0
  fi

  while IFS= read -r line; do
    [[ "${line}" =~ ^([^=]+)=(.*)$ ]] || continue
    curr["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
  done < <(host_context_snapshot)

  theme_section "Context changes since previous snapshot"
  theme_meta_line "Previous: ${prev}"

  while IFS= read -r key; do
    [[ -n "${key}" ]] || continue
    old="$(grep -E "^${key}=" "${prev}" 2>/dev/null | head -n 1 | cut -d= -f2- || true)"
    new="${curr[${key}]:-}"
    [[ -n "${old}" ]] || continue
    if [[ "${old}" != "${new}" ]]; then
      warn "${key}: ${old} → ${new}"
    fi
  done <<'EOF'
research_profile
fw_default_zone
fw_strict_ok
mariadb_public
avahi
llmnr
cups
listeners
wifi_radio
wired_connected
selinux
failed_units
data_mount
sudo_nopass
EOF
}

# Research-host posture: prints OK or issue count + top issues
host_context_posture_summary() {
  local n=0 issue
  if ! host_context_is_research_host; then
    printf 'desktop (no research posture checks)\n'
    return 0
  fi
  while IFS= read -r issue; do
    [[ -n "${issue}" ]] || continue
    n=$((n + 1))
  done < <(host_context_research_issues)
  if (( n == 0 )); then
    printf 'research posture OK\n'
  else
    printf 'research posture: %s issue(s)\n' "${n}"
  fi
}

host_context_research_issues() {
  host_context_is_research_host || return 0
  network_research_listening_issues
  if network_firewall_zone_readable; then
    network_firewall_zone_is_strict "$(network_firewall_default_zone 2>/dev/null || true)" 2>/dev/null \
      || printf '%s\n' "Firewall default zone not strict (ssh-only)"
  elif network_firewall_active; then
    printf '%s\n' "Firewall zone details need sudo for verification"
  fi
  network_wired_ethernet_connected || printf '%s\n' "No wired Ethernet link connected"
  system_state_selinux_enforcing || printf '%s\n' "SELinux not enforcing"
  system_state_data_mounted || printf '%s\n' "/data not mounted"
}

# ---------- snapshot (machine-readable key=value) ----------
host_context_snapshot() {
  local zone def listeners posture n=0
  zone="$(network_firewall_strict_zone_name)"
  def="$(network_firewall_default_zone 2>/dev/null || echo unknown)"
  listeners="$(network_listener_summary | tr '\n' ' ')"
  posture="$(host_context_posture_summary | tr -d '\n')"
  while IFS= read -r _; do n=$((n + 1)); done < <(host_context_research_issues 2>/dev/null || true)

  printf 'host=%s\n' "$(health_hostname)"
  printf 'os=%s\n' "$(system_state_os_label | tr -d '\n')"
  printf 'kernel=%s\n' "$(health_kernel)"
  printf 'session=%s\n' "$(users_session_kind)"
  printf 'session_label=%s\n' "$(users_session_label | tr -d '\n')"
  printf 'invoker=%s\n' "$(real_user)"
  printf 'invoker_home=%s\n' "$(real_home)"
  printf 'effective_user=%s\n' "$(id -un 2>/dev/null || echo unknown)"
  printf 'research_profile=%s\n' "$(host_context_is_research_host && echo yes || echo no)"
  printf 'posture=%s\n' "${posture}"
  printf 'posture_issues=%s\n' "${n}"
  printf 'login_accounts=%s\n' "$(users_detect_login | tr ' ' ',')"
  printf 'wheel_accounts=%s\n' "$(users_detect_wheel 2>/dev/null | tr ' ' ',' || echo none)"
  printf 'login_count=%s\n' "$(users_count_login_accounts)"
  printf 'wheel_count=%s\n' "$(users_count_wheel_accounts)"
  printf 'selinux=%s\n' "$(system_state_selinux_mode | tr -d '\n')"
  printf 'sudo=%s\n' "$(system_state_sudo_available && echo yes || echo no)"
  printf 'sudo_nopass=%s\n' "$(system_state_sudo_passwordless && echo yes || echo no)"
  printf 'data_mount=%s\n' "$(system_state_data_mounted && echo yes || echo no)"
  printf 'root_disk_pct=%s\n' "$(health_root_disk_pct 2>/dev/null || echo unknown)"
  printf 'firewalld=%s\n' "$(network_firewall_active && echo running || echo no)"
  printf 'fw_zone_readable=%s\n' "$(network_firewall_zone_readable && echo yes || echo no)"
  printf 'fw_default_zone=%s\n' "${def:-unknown}"
  printf 'fw_strict_zone=%s\n' "${zone}"
  printf 'fw_strict_ok=%s\n' "$(network_firewall_zone_is_strict "${def}" 2>/dev/null && echo yes || echo no)"
  printf 'listeners=%s\n' "${listeners}"
  printf 'unexpected_public=%s\n' "$(network_unexpected_public_count)"
  printf 'mariadb_public=%s\n' "$(network_mariadb_listens_public && echo yes || echo no)"
  printf 'avahi=%s\n' "$(network_listening_has_avahi && echo yes || echo no)"
  printf 'llmnr=%s\n' "$(network_listening_has_llmnr && echo yes || echo no)"
  printf 'cups=%s\n' "$(network_listening_has_cups && echo yes || echo no)"
  printf 'wifi_radio=%s\n' "$(network_wifi_radio_state 2>/dev/null || echo unknown)"
  printf 'wired_connected=%s\n' "$(network_wired_ethernet_connected && echo yes || echo no)"
  printf 'httpd=%s\n' "$(system_state_service_active httpd | tr -d '\n')"
  printf 'tools=%s\n' "$(system_state_tools_present | tr ' ' ',')"
  printf 'failed_units=%s\n' "$(system_state_failed_units_count)"
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    printf 'ssh_from=%s\n' "$(users_ssh_client_address 2>/dev/null || echo unknown)"
  fi
}

# Legacy alias — snapshot without saving
host_context_snapshot_live() {
  host_context_snapshot
}

host_context_print_banner() {
  theme_meta_line "Host: $(health_hostname) · OS: $(system_state_os_label | tr -d '\n')"
  theme_meta_line "Session: $(users_session_label | tr -d '\n')"
  theme_meta_line "Hardening: $(host_context_research_label | tr -d '\n')"
  theme_meta_line "Posture: $(host_context_posture_summary | tr -d '\n')"
  theme_meta_line "User: $(users_invoker_summary | tr -d '\n')"
  if system_state_data_mounted; then
    theme_meta_line "Data: $(system_state_mount_line /data | tr -d '\n')"
  fi
}

# Human-readable multi-line summary for doctors/audits
host_context_print_summary() {
  local zone def issue
  zone="$(network_firewall_strict_zone_name)"
  def="$(network_firewall_default_zone 2>/dev/null || echo unknown)"

  echo "Host context"
  echo "  Hostname     : $(health_hostname)"
  echo "  OS           : $(system_state_os_label | tr -d '\n')"
  echo "  Session      : $(users_session_label | tr -d '\n')"
  echo "  Invoker      : $(users_invoker_summary)"
  echo "  Research     : $(host_context_is_research_host && echo yes || echo no)"
  echo "  Posture      : $(host_context_posture_summary | tr -d '\n')"
  echo "  Login users  : $(users_detect_login)"
  echo "  Wheel users  : $(users_detect_wheel 2>/dev/null || echo none)"
  echo "  SELinux      : $(system_state_selinux_mode)"
  echo "  Sudo         : $(system_state_sudo_available && echo available || echo missing) ($(system_state_sudo_passwordless && echo passwordless || echo needs password))"
  echo "  /data        : $(system_state_data_mounted && system_state_mount_line /data || echo not mounted)"
  echo "  firewalld    : $(network_firewall_active && echo running || echo inactive)"
  echo "  FW default   : ${def} ($(network_firewall_zone_readable && echo readable || echo sudo needed))"
  echo "  FW strict    : ${zone} ($(network_firewall_zone_is_strict "${def}" 2>/dev/null && echo ok || echo review))"
  echo "  Listeners    : $(network_listener_summary | tr '\n' ' ') unexpected_public=$(network_unexpected_public_count)"
  echo "  Wi-Fi radio  : $(network_wifi_radio_state 2>/dev/null || echo unknown)"
  echo "  Wired link   : $(network_wired_ethernet_connected && echo connected || echo none)"
  echo "  Failed units : $(system_state_failed_units_count)"
  if host_context_is_research_host; then
    while IFS= read -r issue; do
      [[ -n "${issue}" ]] || continue
      echo "  ! ${issue}"
    done < <(host_context_research_issues)
  fi
}

# Remediation hints based on context (no system changes)
host_context_remediation_notes() {
  if ! system_state_sudo_available; then
    warn "sudo not available — privileged fixes will fail"
  elif ! system_state_sudo_passwordless; then
    info "sudo requires a password — run remediation commands in an interactive terminal"
  fi
  if ! network_firewall_available; then
    warn "firewall-cmd not available"
  elif ! network_firewall_active; then
    warn "firewalld not running — firewall checks may be incomplete"
  elif ! network_firewall_zone_readable; then
    warn "firewalld running but zone details need sudo — run: sudo ./system/host_context.sh --save"
  fi
  if host_context_is_research_host && ! network_wired_ethernet_connected; then
    warn "Research profile but no wired Ethernet link — verify before disabling Wi-Fi"
  fi
  if [[ "$(users_count_wheel_accounts)" -gt 1 ]] && host_context_is_research_host; then
    info "Multiple wheel accounts ($(users_detect_wheel)) — ensure SSH AllowUsers is set"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
