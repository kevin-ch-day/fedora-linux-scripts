#!/usr/bin/env bash
# lib/network.sh — interfaces, listeners, firewalld, and radio state
# Version: 0.1.1
#
# Read-only network visibility. Source after lib/common.sh.

if [[ -n "${FEDORA_NETWORK_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_NETWORK_SH_LOADED=1

_NETWORK_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_NETWORK_LIB_DIR}/common.sh"
# shellcheck source=health.sh
source "${_NETWORK_LIB_DIR}/health.sh"

# ---------- privileged read (no changes) ----------
network_run_readonly() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@" 2>&1 || printf '[exit %s]\n' "$?"
  elif have sudo; then
    sudo "$@" 2>&1 || printf '[exit %s]\n' "$?"
  else
    "$@" 2>&1 || printf '[exit %s]\n' "$?"
  fi
}

network_run_readonly_capture() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@" 2>/dev/null
  elif have sudo; then
    sudo "$@" 2>/dev/null
  else
    "$@" 2>/dev/null
  fi
}

# ---------- sockets / listeners ----------
network_ss_listening() {
  network_run_readonly_capture ss -tulpen
}

network_ss_established() {
  network_run_readonly_capture ss -tunap state established
}

# Non-localhost listeners (0.0.0.0, *, [::])
network_public_listeners() {
  network_ss_listening \
    | awk '/LISTEN/ {
      if ($0 ~ /127\.0\.0\.1:/ || $0 ~ /\[::1\]:/) next
      if ($0 ~ /0\.0\.0\.0:/ || $0 ~ /\*:/ || $0 ~ /\[::\]:/) print
    }'
}

network_localhost_listeners() {
  network_ss_listening \
    | awk '/LISTEN/ {
      if ($0 ~ /127\.0\.0\.1:/ || $0 ~ /\[::1\]:/) print
    }'
}

network_listener_summary() {
  local pub loc
  pub="$(network_public_listeners | wc -l | tr -d ' ')"
  loc="$(network_localhost_listeners | wc -l | tr -d ' ')"
  printf 'public=%s localhost=%s\n' "${pub}" "${loc}"
}

network_listening_on_port() {
  local port="$1"
  network_ss_listening | grep -E ":${port}[[:space:]]|:${port}\$"
}

network_listening_has_avahi() {
  network_ss_listening | grep -qE ':5353.*avahi|:5353.*5353'
}

network_listening_has_llmnr() {
  network_ss_listening | grep -qE ':5355'
}

network_listening_has_cups() {
  network_ss_listening | grep -qE ':631'
}

network_mariadb_listens_public() {
  network_ss_listening | grep -E ':3306' | grep -qE '0\.0\.0\.0:3306|\[::\]:3306|\*:3306'
}

network_ssh_listens_public() {
  network_ss_listening | grep -qE '0\.0\.0\.0:22|\[::\]:22|\*:22'
}

# ---------- nmcli / links ----------
network_nmcli_available() {
  have nmcli && nmcli general status >/dev/null 2>&1
}

network_print_radios() {
  network_nmcli_available || return 1
  nmcli radio all 2>/dev/null
}

network_print_devices() {
  network_nmcli_available || return 1
  nmcli device status 2>/dev/null
}

network_wifi_radio_state() {
  network_nmcli_available || { printf 'unknown\n'; return 1; }
  nmcli radio wifi 2>/dev/null | head -n 1 | tr '[:upper:]' '[:lower:]'
}

network_wifi_radio_off() {
  network_nmcli_available || return 1
  network_wifi_radio_state | grep -qx disabled
}

network_wifi_rfkill_blocked() {
  have rfkill || return 1
  rfkill list wifi 2>/dev/null | grep -q 'Soft blocked: yes'
}

network_wired_ethernet_connected() {
  network_nmcli_available || return 1
  nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null \
    | awk -F: '$2 == "ethernet" && $3 == "connected" { found=1 } END { exit !found }'
}

network_primary_interfaces() {
  if network_nmcli_available; then
    nmcli -t -f DEVICE,STATE device status 2>/dev/null \
      | awk -F: '$2 ~ /connected/ {print $1}' | grep -v '^lo$' || true
    return 0
  fi
  ip -o link show up 2>/dev/null | awk -F': ' '{print $2}' | awk '{print $1}' | grep -v '^lo$' || true
}

network_default_route_iface() {
  ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1); exit}' || true
}

network_ipv4_summary() {
  ip -br -4 addr 2>/dev/null || true
}

# ---------- firewalld ----------
network_host_slug() {
  health_hostname \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9._-' '-' \
    | sed -e 's/^-*//' -e 's/-*$//' -e 's/-\{2,\}/-/g'
}

network_firewall_strict_zone_name() {
  if [[ -n "${FEDORA_HARDENING_FIREWALL_ZONE:-}" ]]; then
    printf '%s\n' "${FEDORA_HARDENING_FIREWALL_ZONE}"
    return 0
  fi
  local slug
  slug="$(network_host_slug)"
  [[ -n "${slug}" ]] || slug="host"
  printf '%s-research\n' "${slug}"
}

network_firewall_cmd() {
  local out=""
  if [[ "${EUID}" -eq 0 ]]; then
    out="$(firewall-cmd "$@" 2>/dev/null || true)"
  elif have sudo; then
    out="$(sudo firewall-cmd "$@" 2>/dev/null || true)"
  else
    return 1
  fi
  printf '%s\n' "${out}"
}

network_firewall_available() {
  have firewall-cmd
}

network_firewall_active() {
  if [[ "$(network_firewall_cmd --state 2>/dev/null | head -n 1 | tr '[:upper:]' '[:lower:]')" == "running" ]]; then
    return 0
  fi
  [[ "$(systemctl is-active firewalld 2>/dev/null | head -n 1)" == "active" ]]
}

network_firewall_zone_readable() {
  local z
  z="$(network_firewall_default_zone 2>/dev/null || true)"
  [[ -n "${z}" && "${z}" != "unknown" ]]
}

# SSH on :22 is the only expected public listener on research hosts.
network_listener_is_expected_public() {
  local line="$1"
  grep -qE '(:|\*)22[[:space:]]|:22$|\[::\]:22' <<< "${line}"
}

network_unexpected_public_listeners() {
  local line
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    network_listener_is_expected_public "${line}" && continue
    printf '%s\n' "${line}"
  done < <(network_public_listeners)
}

network_unexpected_public_count() {
  network_unexpected_public_listeners | wc -l | tr -d ' '
}

# One issue per line (empty = OK). Research-host listening posture.
network_research_listening_issues() {
  network_mariadb_listens_public && printf '%s\n' "MariaDB listening on 0.0.0.0/[::]:3306"
  network_listening_has_avahi && printf '%s\n' "Avahi/mDNS (UDP 5353)"
  network_listening_has_llmnr && printf '%s\n' "LLMNR (UDP 5355)"
  network_listening_has_cups && printf '%s\n' "CUPS (TCP 631)"
  if network_unexpected_public_listeners | grep -q .; then
    network_unexpected_public_listeners | head -n 3 | while IFS= read -r line; do
      printf 'Unexpected public listener: %s\n' "${line}"
    done
  fi
}

network_firewall_default_zone() {
  network_firewall_cmd --get-default-zone | head -n 1 | tr -d '[:space:]'
}

network_firewall_zone_exists() {
  local zone="$1"
  [[ -n "${zone}" ]] || return 1
  network_firewall_cmd --get-zones 2>/dev/null | tr ' ' '\n' | grep -qx "${zone}"
}

network_firewall_zone_of_interface() {
  local iface="$1"
  network_firewall_cmd --get-zone-of-interface="${iface}" | head -n 1 | tr -d '[:space:]'
}

network_firewall_interfaces_in_zone() {
  local zone="$1"
  network_firewall_cmd --info-zone="${zone}" 2>/dev/null \
    | awk -F: '/^[[:space:]]*interfaces:/ {gsub(/^[ \t]+/,"",$2); print $2}'
}

network_firewall_zone_services() {
  local zone="$1"
  network_firewall_cmd --zone="${zone}" --list-services 2>/dev/null | tr ' ' '\n' | grep -v '^$' || true
}

network_firewall_zone_ports() {
  local zone="$1"
  network_firewall_cmd --zone="${zone}" --list-ports 2>/dev/null | tr ' ' '\n' | grep -v '^$' || true
}

network_firewall_zone_has_wide_ports() {
  local zone="$1"
  network_firewall_zone_ports "${zone}" | grep -qE '1025-65535|1-65535'
}

# Default zone, ssh-only services, no wide ports
network_firewall_zone_is_strict() {
  local zone="${1:-$(network_firewall_strict_zone_name)}"
  local def svcs svc
  def="$(network_firewall_default_zone)"
  [[ -n "${def}" && "${def}" == "${zone}" ]] || return 1
  network_firewall_zone_has_wide_ports "${zone}" && return 1
  [[ -z "$(network_firewall_zone_ports "${zone}")" ]] || return 1
  svcs="$(network_firewall_zone_services "${zone}")"
  [[ -n "${svcs}" ]] || return 1
  while read -r svc; do
    [[ -n "${svc}" ]] || continue
    [[ "${svc}" == ssh ]] && continue
    return 1
  done <<< "${svcs}"
  grep -qx ssh <<< "${svcs}"
}

network_firewall_print_zone() {
  local zone="$1"
  local svcs ports
  svcs="$(network_firewall_zone_services "${zone}" | tr '\n' ' ' | sed 's/ $//')"
  ports="$(network_firewall_zone_ports "${zone}" | tr '\n' ' ' | sed 's/ $//')"
  printf 'zone=%s services=[%s] ports=[%s]\n' "${zone}" "${svcs:-none}" "${ports:-none}"
}

network_firewall_active_wired_connections() {
  network_nmcli_available || return 0
  nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>/dev/null \
    | awk -F: '$2 == "802-3-ethernet" && $3 != "" { print $1 }'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
