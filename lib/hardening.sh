#!/usr/bin/env bash
# lib/hardening.sh — OS hardening helpers (host/OS/user detection)
# Version: 0.6.0
#
# Source after lib/common.sh. Used by system/hardening_round1.sh and audit scripts.

if [[ -n "${FEDORA_HARDENING_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_HARDENING_SH_LOADED=1

_HARDENING_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_HARDENING_LIB_DIR}/common.sh"
# shellcheck source=health.sh
source "${_HARDENING_LIB_DIR}/health.sh"
# shellcheck source=logging.sh
source "${_HARDENING_LIB_DIR}/logging.sh"
# shellcheck source=users.sh
source "${_HARDENING_LIB_DIR}/users.sh"
# shellcheck source=network.sh
source "${_HARDENING_LIB_DIR}/network.sh"
# shellcheck source=host_context.sh
source "${_HARDENING_LIB_DIR}/host_context.sh"

HARDENING_DROPIN_TAG="fedora-toolkit"
HARDENING_DROPIN_HEADER="# Managed by fedora-linux-scripts Round 1 hardening"

# ---------- OS / host identity ----------
hardening_is_fedora() {
  [[ -r /etc/fedora-release ]] && return 0
  [[ -r /etc/os-release ]] && grep -qiE '^ID=fedora' /etc/os-release 2>/dev/null
}

hardening_host_slug() { host_context_host_slug; }
hardening_os_label() { system_state_os_label; }
hardening_invoker_label() {
  local u h
  u="$(real_user)"
  h="$(real_home)"
  printf '%s (%s)\n' "${u}" "${h}"
}

hardening_host_profile() {
  case "$(users_session_kind)" in
    local) printf 'desktop\n' ;;
    ssh|headless) printf 'headless\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

hardening_profile_label() {
  case "$(hardening_host_profile)" in
    desktop) printf 'desktop workstation (GUI session or display manager)\n' ;;
    headless) printf 'headless / remote shell (no local GUI detected)\n' ;;
    *) printf 'unknown (could not classify session)\n' ;;
  esac
}

hardening_has_login_shell() { users_has_login_shell "$@"; }
hardening_is_human_home() { users_is_human_home "$@"; }
hardening_users_sorted_line() { users_sorted_line "$@"; }
hardening_detect_login_users() { users_detect_login; }
hardening_detect_wheel_users() { users_detect_wheel; }
hardening_detect_ssh_allow_users() { users_detect_ssh_allow_candidates; }
hardening_merge_user_lists() { users_merge_lists "$@"; }
hardening_normalize_allow_users() { users_normalize_allow_list "$@"; }
hardening_allow_users_mode_label() { users_allow_mode_label "$@"; }

hardening_resolve_allow_users() {
  local mode="${1:-}" proposed existing
  proposed="$(hardening_normalize_allow_users "${mode}")"
  existing="$(hardening_sshd_effective_allow_users 2>/dev/null || true)"
  if [[ -n "${existing}" ]]; then
    hardening_merge_user_lists "${existing}" "${proposed}"
  else
    printf '%s\n' "${proposed}"
  fi
}

# sshd effective config
hardening_sshd_effective_key() {
  local key="$1"
  local run_as_root="${2:-0}"
  local out
  if (( run_as_root )) || [[ "${EUID}" -eq 0 ]]; then
    out="$(sshd -T 2>/dev/null | awk -v k="${key}" 'tolower($1)==tolower(k) { $1=""; sub(/^ /,""); print; exit }' || true)"
  elif have sudo; then
    out="$(sudo sshd -T 2>/dev/null | awk -v k="${key}" 'tolower($1)==tolower(k) { $1=""; sub(/^ /,""); print; exit }' || true)"
  fi
  printf '%s\n' "${out}"
}

hardening_sshd_effective_allow_users() {
  hardening_sshd_effective_key allowusers 0
}

# ---------- paths / drop-ins ----------
hardening_baseline_root() {
  local override="${1:-}"
  if [[ -n "${override}" ]]; then
    printf '%s\n' "${override}"
    return 0
  fi
  if [[ -n "${FEDORA_HARDENING_LOG_ROOT:-}" ]]; then
    printf '%s\n' "${FEDORA_HARDENING_LOG_ROOT}"
    return 0
  fi
  if findmnt -n /data >/dev/null 2>&1 && [[ -d /data && -w /data ]]; then
    printf '%s\n' "/data/logs/hardening"
    return 0
  fi
  printf '%s\n' "$(log_dir)/hardening"
}

hardening_baseline_session_dir() {
  local base_root="$1"
  local stamp="$2"
  local slug
  slug="$(hardening_host_slug)"
  [[ -n "${slug}" ]] || slug="host"
  printf '%s/%s/%s\n' "${base_root}" "${slug}" "${stamp}"
}

hardening_baseline_report_path() {
  local session_dir="$1"
  printf '%s/host_baseline.txt\n' "${session_dir}"
}

hardening_latest_baseline_report() {
  local root slug dir
  root="$(hardening_baseline_root)"
  slug="$(hardening_host_slug)"
  dir="$(find "${root}/${slug}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -n 1 || true)"
  [[ -n "${dir}" && -f "${dir}/host_baseline.txt" ]] || return 1
  printf '%s/host_baseline.txt\n' "${dir}"
}

hardening_sshd_dropin() {
  printf '/etc/ssh/sshd_config.d/90-%s-round1.conf\n' "${HARDENING_DROPIN_TAG}"
}

hardening_sysctl_dropin() {
  printf '/etc/sysctl.d/90-%s-network.conf\n' "${HARDENING_DROPIN_TAG}"
}

hardening_journald_dropin() {
  printf '/etc/systemd/journald.conf.d/90-%s-journald.conf\n' "${HARDENING_DROPIN_TAG}"
}

hardening_dropin_is_ours() {
  local path="$1"
  [[ -f "${path}" ]] || return 1
  grep -qF "${HARDENING_DROPIN_HEADER}" "${path}" 2>/dev/null
}

# ---------- step status (read-only) ----------
hardening_selinux_enforcing() {
  [[ "$(getenforce 2>/dev/null || true)" == Enforcing ]]
}

hardening_selinux_config_enforcing() {
  [[ -f /etc/selinux/config ]] && grep -qE '^SELINUX=enforcing' /etc/selinux/config 2>/dev/null
}

hardening_sysctl_hardened() {
  local path
  path="$(hardening_sysctl_dropin)"
  hardening_dropin_is_ours "${path}" && return 0
  [[ "$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null || echo 0)" == 1 ]] \
    && [[ "$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null || echo 0)" == 1 ]]
}

hardening_journald_persistent() {
  local path dropin_ok storage
  path="$(hardening_journald_dropin)"
  if hardening_dropin_is_ours "${path}"; then
    return 0
  fi
  storage="$(grep -E '^Storage=' /etc/systemd/journald.conf /etc/systemd/journald.conf.d/*.conf 2>/dev/null \
    | tail -n 1 | cut -d= -f2 | tr -d ' ' || true)"
  [[ "${storage}" == persistent ]]
}

hardening_firewall_ssh_allowed() {
  have firewall-cmd || return 1
  local out=""
  if [[ "${EUID}" -eq 0 ]]; then
    out="$(firewall-cmd --list-services 2>/dev/null || true)"
  elif have sudo; then
    out="$(sudo firewall-cmd --list-services 2>/dev/null || true)"
  else
    return 1
  fi
  grep -qw ssh <<< "${out}"
}

hardening_unit_ok() {
  local unit="$1"
  systemctl is-enabled --quiet "${unit}" 2>/dev/null
}

hardening_sshd_round1_applied() {
  local path
  path="$(hardening_sshd_dropin)"
  hardening_dropin_is_ours "${path}"
}

hardening_step_status() {
  local step="$1"
  case "${step}" in
    selinux)
      hardening_selinux_enforcing && hardening_selinux_config_enforcing && printf 'ok\n' || printf 'needs\n'
      ;;
    ssh)
      hardening_sshd_round1_applied && printf 'ok\n' || printf 'needs\n'
      ;;
    sysctl)
      hardening_sysctl_hardened && printf 'ok\n' || printf 'needs\n'
      ;;
    journald)
      hardening_journald_persistent && printf 'ok\n' || printf 'needs\n'
      ;;
    firewall)
      hardening_unit_ok firewalld && hardening_unit_ok fstrim.timer && hardening_firewall_ssh_allowed \
        && printf 'ok\n' || printf 'needs\n'
      ;;
    *) printf 'unknown\n' ;;
  esac
}

hardening_round1_complete() {
  local step
  for step in selinux ssh sysctl journald firewall; do
    [[ "$(hardening_step_status "${step}")" == ok ]] || return 1
  done
  return 0
}

hardening_print_host_banner_meta() {
  host_context_print_banner
}

hardening_preflight_or_warn() {
  if hardening_is_fedora; then
    ok "OS: $(hardening_os_label | tr -d '\n')"
    return 0
  fi
  warn "OS: $(hardening_os_label | tr -d '\n') — scripts target Fedora; proceed with care"
  return 1
}

hardening_print_round1_status() {
  local step status label
  theme_section "Round 1 status on $(health_hostname)"
  for step in selinux ssh sysctl journald firewall; do
    status="$(hardening_step_status "${step}")"
    case "${step}" in
      selinux) label="SELinux enforcing" ;;
      ssh) label="SSH Round 1 drop-in" ;;
      sysctl) label="Network sysctl hardening" ;;
      journald) label="Persistent journald" ;;
      firewall) label="firewalld + fstrim + ssh" ;;
    esac
    case "${status}" in
      ok) theme_status_ok "${label}" ;;
      needs) theme_status_warn "${label} — not applied or incomplete" ;;
      *) theme_status_info "${label} — ${status}" ;;
    esac
  done
  echo
  if hardening_round1_complete; then
    theme_status_ok "Round 1: complete on this host"
  else
    theme_status_info "Round 1: incomplete — run ./system/hardening_round1.sh --yes"
  fi
  local latest
  if latest="$(hardening_latest_baseline_report 2>/dev/null)"; then
    theme_meta_line "Latest baseline: ${latest}"
  fi
}

hardening_print_round1_plan() {
  local allow_users="${1:-}"
  local resolved
  resolved="$(hardening_resolve_allow_users "${allow_users}")"
  theme_section "Planned changes"
  theme_meta_line "AllowUsers mode: $(hardening_allow_users_mode_label "${allow_users:-auto}" | tr -d '\n')"
  theme_meta_line "AllowUsers resolved: ${resolved}"
  local existing
  existing="$(hardening_sshd_effective_allow_users 2>/dev/null || true)"
  if [[ -n "${existing}" && "${existing}" != "${resolved}" ]]; then
    theme_meta_line "Existing sshd AllowUsers merged in (no lockout)"
  fi
  echo
  local step status
  for step in selinux ssh sysctl journald firewall; do
    status="$(hardening_step_status "${step}")"
    if [[ "${status}" == ok ]]; then
      info "${step}: already configured (will skip unless --force)"
    else
      info "${step}: will apply"
    fi
  done
}

# Core services: only list units relevant to installed software / profile.
hardening_core_service_units() {
  local profile
  profile="$(hardening_host_profile)"
  printf '%s\n' sshd firewalld fstrim.timer NetworkManager
  if rpm -q mariadb-server >/dev/null 2>&1 || rpm -q mariadb >/dev/null 2>&1; then
    printf '%s\n' mariadb
  fi
  if [[ "${profile}" == desktop ]]; then
    printf '%s\n' gdm
  fi
}

# Round 2 candidates: name|reason|profile (any|desktop|headless)
hardening_round2_candidates() {
  printf '%s\n' \
    "avahi-daemon|Local network discovery|any" \
    "cups|Printing|desktop" \
    "bluetooth|Bluetooth stack|desktop" \
    "cockpit.socket|Web admin interface|any" \
    "rpcbind|NFS/RPC support|any" \
    "nfs-server|Network file sharing|any" \
    "smb|Samba file sharing|any" \
    "nmb|Samba NetBIOS|any"
}

hardening_round2_relevant_for_profile() {
  local profile_tag="$1"
  local host_profile
  host_profile="$(hardening_host_profile)"
  case "${profile_tag}" in
    any) return 0 ;;
    desktop) [[ "${host_profile}" == desktop ]] && return 0 ;;
    headless) [[ "${host_profile}" == headless ]] && return 0 ;;
    *) return 0 ;;
  esac
  return 1
}

hardening_package_installed() {
  rpm -q "$1" >/dev/null 2>&1
}

# ---------- Round 2: firewall + services ----------
# Custom strict zone: <hostname-slug>-research (override: FEDORA_HARDENING_FIREWALL_ZONE)
hardening_firewall_strict_zone_name() { network_firewall_strict_zone_name; }

hardening_firewall_log_dir() {
  local root
  root="$(hardening_baseline_root)"
  printf '%s/firewall\n' "${root}"
}

hardening_firewall_cmd() { network_firewall_cmd "$@"; }
hardening_firewall_zone_exists() { network_firewall_zone_exists "$@"; }
hardening_is_research_host() { host_context_is_research_host; }
hardening_research_profile_label() { host_context_research_label; }
hardening_firewall_default_zone() { network_firewall_default_zone; }
hardening_firewall_zone_of_interface() { network_firewall_zone_of_interface "$@"; }
hardening_firewall_interfaces_in_zone() { network_firewall_interfaces_in_zone "$@"; }
hardening_firewall_zone_services() { network_firewall_zone_services "$@"; }
hardening_firewall_zone_ports() { network_firewall_zone_ports "$@"; }
hardening_firewall_zone_has_wide_ports() { network_firewall_zone_has_wide_ports "$@"; }

hardening_firewall_print_zone_summary() {
  local zone="$1" svcs ports
  svcs="$(network_firewall_zone_services "${zone}" | tr '\n' ' ' | sed 's/ $//')"
  ports="$(network_firewall_zone_ports "${zone}" | tr '\n' ' ' | sed 's/ $//')"
  theme_meta_line "  Zone ${zone}: services=[${svcs:-none}] ports=[${ports:-none}]"
}

hardening_firewall_primary_interfaces() { network_primary_interfaces; }
hardening_round2_firewall_is_strict() { network_firewall_zone_is_strict "$@"; }

hardening_round2_firewall_needs_hardening() {
  have firewall-cmd || return 1
  local def loose
  def="$(hardening_firewall_default_zone)"
  if [[ "${def}" == FedoraWorkstation || "${def}" == workstation ]]; then
    return 0
  fi
  if hardening_round2_firewall_is_strict "${def}"; then
    return 1
  fi
  if hardening_round2_firewall_is_strict "$(hardening_firewall_strict_zone_name)"; then
    return 1
  fi
  for loose in FedoraWorkstation workstation; do
    hardening_firewall_zone_has_wide_ports "${loose}" && return 0
  done
  return 0
}

hardening_firewall_active_wired_connections() { network_firewall_active_wired_connections; }

hardening_firewall_run_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

hardening_firewall_save_snapshot() {
  local label="$1"
  local out="$2"
  mkdir -p "$(dirname "${out}")"
  {
    echo "===== METADATA ====="
    echo "Captured: $(date -Iseconds)"
    echo "Hostname: $(health_hostname)"
    echo "Label: ${label}"
    echo
    echo "===== DEFAULT ZONE ====="
    hardening_firewall_cmd --get-default-zone
    echo
    echo "===== ACTIVE ZONES ====="
    hardening_firewall_cmd --get-active-zones
    echo
    echo "===== DEFAULT ZONE RULES ====="
    hardening_firewall_cmd --list-all
    echo
    echo "===== STRICT ZONE ($(hardening_firewall_strict_zone_name)) ====="
    hardening_firewall_cmd --zone="$(hardening_firewall_strict_zone_name)" --list-all
    echo
    echo "===== NM DEVICES ====="
    nmcli device status 2>/dev/null || true
    echo
    echo "===== ACTIVE CONNECTIONS ====="
    nmcli connection show --active 2>/dev/null || true
    echo
    echo "===== LISTENING (ss -tulpen) ====="
    hardening_firewall_run_root ss -tulpen 2>/dev/null || ss -tulpen 2>/dev/null || true
  } | tee "${out}"
}

hardening_print_listening_services() {
  theme_section "Listening TCP/UDP (ss -tulpen)"
  if [[ "${EUID}" -eq 0 ]]; then
    ss -tulpen 2>/dev/null | sed 's/^/  /' || true
  elif have sudo; then
    sudo ss -tulpen 2>/dev/null | sed 's/^/  /' || true
  else
    ss -tulpen 2>/dev/null | sed 's/^/  /' || true
  fi
}

hardening_check_mariadb_not_firewalled() {
  local zone ports
  zone="$(hardening_firewall_strict_zone_name)"
  ports="$(hardening_firewall_zone_ports "${zone}")"
  if grep -qE '3306|mysql' <<< "${ports}"; then
    warn "MariaDB/MySQL port open in firewall zone ${zone} — should be local only"
    return 1
  fi
  if grep -qE '3306|mysql' <<< "$(hardening_firewall_zone_services "${zone}")"; then
    warn "MariaDB/MySQL service open in firewall zone ${zone}"
    return 1
  fi
  ok "MariaDB: not exposed in firewall zone ${zone}"
  return 0
}

# Apply custom strict zone: ssh only, wired NM connections bound to zone.
# Usage: hardening_firewall_apply_strict [dry_run=0]
hardening_firewall_apply_strict() {
  local dry_run="${1:-0}"
  local zone svc port conn loose loose_zone
  zone="$(hardening_firewall_strict_zone_name)"

  if ! have firewall-cmd; then
    warn "firewalld not installed — skipping firewall hardening"
    return 1
  fi

  if (( dry_run )); then
    info "[dry-run] create/use zone ${zone}; ssh only; bind wired NM connections"
    while IFS= read -r conn; do
      [[ -n "${conn}" ]] || continue
      info "[dry-run]   nmcli connection modify '${conn}' connection.zone ${zone}"
    done < <(hardening_firewall_active_wired_connections)
    info "[dry-run] firewall-cmd --set-default-zone=${zone}; --reload"
    return 0
  fi

  hardening_firewall_run_root firewall-cmd --permanent --new-zone="${zone}" 2>/dev/null || true
  hardening_firewall_run_root firewall-cmd --permanent --zone="${zone}" --set-target=default
  hardening_firewall_run_root firewall-cmd --permanent --zone="${zone}" --add-service=ssh

  for svc in samba-client dhcpv6-client cockpit mdns samba http https mysql mariadb; do
    hardening_firewall_run_root firewall-cmd --permanent --zone="${zone}" --remove-service="${svc}" 2>/dev/null || true
  done

  for port in 1025-65535/tcp 1025-65535/udp 3306/tcp 80/tcp 443/tcp 9090/tcp; do
    hardening_firewall_run_root firewall-cmd --permanent --zone="${zone}" --remove-port="${port}" 2>/dev/null || true
  done

  while read -r svc; do
    [[ -n "${svc}" && "${svc}" != ssh ]] || continue
    hardening_firewall_run_root firewall-cmd --permanent --zone="${zone}" --remove-service="${svc}" 2>/dev/null || true
  done < <(hardening_firewall_zone_services "${zone}")

  while read -r port; do
    [[ -n "${port}" ]] || continue
    hardening_firewall_run_root firewall-cmd --permanent --zone="${zone}" --remove-port="${port}" 2>/dev/null || true
  done < <(hardening_firewall_zone_ports "${zone}")

  hardening_firewall_run_root firewall-cmd --permanent --set-default-zone="${zone}"

  for loose_zone in FedoraWorkstation workstation home trusted; do
    while read -r port; do
      [[ -n "${port}" ]] || continue
      hardening_firewall_run_root firewall-cmd --permanent --zone="${loose_zone}" --remove-port="${port}" 2>/dev/null || true
    done < <(hardening_firewall_zone_ports "${loose_zone}")
  done

  # Reload so runtime zone exists before nmcli connection.zone (avoids INVALID_ZONE).
  hardening_firewall_run_root firewall-cmd --reload

  if hardening_nmcli_available; then
    while IFS=: read -r conn _ device; do
      [[ -n "${conn}" ]] || continue
      info "Assigning wired connection '${conn}' (${device:-iface}) → zone ${zone}"
      hardening_firewall_run_root nmcli connection modify "${conn}" connection.zone "${zone}" 2>/dev/null \
        || warn "nmcli zone assignment failed for ${conn} (will bind interface directly)"
      if [[ -n "${device}" && "${device}" != "--" ]]; then
        hardening_firewall_run_root firewall-cmd --permanent --zone="${zone}" --change-interface="${device}" 2>/dev/null || true
      fi
    done < <(nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>/dev/null \
      | awk -F: '$2 == "802-3-ethernet" && $3 != "" { print }')
  fi

  hardening_firewall_run_root firewall-cmd --set-default-zone="${zone}"
  hardening_firewall_run_root firewall-cmd --reload
  ok "Firewall: zone ${zone} active (ssh only, no wide ports)"
}

hardening_print_firewall_verify() {
  local zone
  zone="$(hardening_firewall_strict_zone_name)"
  theme_section "Firewall verify"
  theme_meta_line "Default zone: $(hardening_firewall_default_zone)"
  hardening_firewall_cmd --get-active-zones 2>/dev/null | sed 's/^/  /' || true
  echo
  hardening_firewall_print_zone_summary "${zone}"
  hardening_check_mariadb_not_firewalled || true
}

# unit|reason|tier (safe|review)
hardening_round2_service_units() {
  printf '%s\n' \
    "bluetooth|Bluetooth stack|safe" \
    "avahi-daemon|Local network discovery (mDNS)|safe" \
    "avahi-daemon.socket|Avahi socket|safe" \
    "cups|Printing daemon|safe" \
    "cups.socket|Printing socket|safe" \
    "ModemManager|Cellular modem manager|safe" \
    "cockpit.socket|Web admin interface|safe" \
    "rpcbind|RPC portmapper|safe" \
    "nfs-server|NFS file sharing|safe" \
    "smb|Samba server|safe" \
    "nmb|Samba NetBIOS|safe" \
    "qemu-guest-agent|QEMU VM guest agent|review" \
    "vboxservice|VirtualBox guest service|review" \
    "vmtoolsd|VMware guest tools|review" \
    "systemd-homed|systemd home directories|review" \
    "systemd-homed-activate|systemd homed activation|review" \
    "sssd|System Security Services (domain/LDAP)|review" \
    "sssd-kcm|SSSD Kerberos cache manager|review"
}

hardening_round2_unit_tier() {
  local unit="$1"
  local line tier
  while IFS='|' read -r u _ tier; do
    [[ "${u}" == "${unit}" ]] || continue
    printf '%s\n' "${tier}"
    return 0
  done < <(hardening_round2_service_units)
  printf 'unknown\n'
}

hardening_unit_exists() {
  systemctl cat "$1" >/dev/null 2>&1
}

hardening_unit_is_disabled() {
  local en
  en="$(systemctl is-enabled "$1" 2>/dev/null || true)"
  [[ "${en}" == disabled || "${en}" == masked ]]
}

hardening_round2_service_needs_disable() {
  local unit="$1"
  hardening_unit_exists "${unit}" || return 1
  hardening_unit_is_disabled "${unit}" && return 1
  systemctl is-enabled --quiet "${unit}" 2>/dev/null \
    || systemctl is-active --quiet "${unit}" 2>/dev/null
}

hardening_round2_services_for_run() {
  local include_review="${1:-0}"
  local tier
  while IFS='|' read -r unit _ tier; do
    [[ -n "${unit}" ]] || continue
    if [[ "${tier}" == safe ]]; then
      printf '%s\n' "${unit}"
    elif [[ "${tier}" == review && "${include_review}" == 1 ]]; then
      printf '%s\n' "${unit}"
    fi
  done < <(hardening_round2_service_units)
}

hardening_print_round2_status() {
  local zone strict_ok
  theme_section "Round 2 status on $(health_hostname)"
  if have firewall-cmd; then
    zone="$(hardening_firewall_default_zone)"
    theme_meta_line "Default zone: ${zone:-unknown}"
    hardening_firewall_print_zone_summary "${zone:-public}"
    if hardening_round2_firewall_is_strict "${zone}"; then
      ok "Firewall: strict ($(hardening_firewall_strict_zone_name) · ssh only · no wide ports)"
    else
      warn "Firewall: workstation-style zone or extra services/ports exposed"
    fi
  else
    warn "firewalld not available"
  fi
  echo
  theme_section "Service reduction (safe tier)"
  local unit reason tier
  while IFS='|' read -r unit reason tier; do
    [[ -n "${unit}" ]] || continue
    [[ "${tier}" == safe ]] || continue
    if ! hardening_unit_exists "${unit}"; then
      continue
    fi
    if hardening_unit_is_disabled "${unit}"; then
      ok "${unit}: disabled"
    elif hardening_round2_service_needs_disable "${unit}"; then
      warn "${unit}: enabled/active — candidate to disable"
    else
      info "${unit}: ${unit} — $(systemctl is-enabled "${unit}" 2>/dev/null || echo unknown)"
    fi
  done < <(hardening_round2_service_units)
  echo
  hardening_print_wired_only_status
  echo
  info "Review-tier units (sssd, homed, VM agents): use --include-review to disable"
  info "MariaDB: intentionally not touched — keep local, not exposed via firewall"
}

hardening_print_round2_plan() {
  local profile="${1:-strict}"
  local include_review="${2:-0}"
  local firewall_only="${3:-0}"
  local services_only="${4:-0}"
  theme_section "Round 2 plan (${profile})"
  if [[ "${services_only}" == 0 ]]; then
    if hardening_round2_firewall_needs_hardening; then
      info "Firewall: custom zone $(hardening_firewall_strict_zone_name), ssh only, wired NM binding"
    else
      info "Firewall: already strict (skip unless --force)"
    fi
  fi
  if [[ "${firewall_only}" == 0 ]]; then
    local unit reason tier
    while IFS='|' read -r unit reason tier; do
      [[ -n "${unit}" ]] || continue
      [[ "${tier}" == review && "${include_review}" != 1 ]] && continue
      [[ "${tier}" == safe || "${tier}" == review ]] || continue
      if hardening_round2_service_needs_disable "${unit}"; then
        info "Disable: ${unit} — ${reason}"
      fi
    done < <(hardening_round2_service_units)
  fi
  theme_meta_line "Password SSH login: unchanged (Round 1 drop-in kept)"
  theme_meta_line "MariaDB: not disabled; not added to firewall"
}

# ---------- Wired-only: disable Bluetooth + Wi-Fi ----------
hardening_nmcli_available() { network_nmcli_available; }

hardening_print_nmcli_radios() {
  network_nmcli_available || { warn "nmcli not available"; return 1; }
  network_print_radios | sed 's/^/  /'
}

hardening_print_nmcli_devices() {
  network_nmcli_available || return 1
  network_print_devices | sed 's/^/  /'
}

hardening_wired_ethernet_connected() { network_wired_ethernet_connected; }
hardening_wifi_radio_off() { network_wifi_radio_off; }
hardening_wifi_rfkill_blocked() { network_wifi_rfkill_blocked; }

hardening_bluetooth_unit_state() {
  printf 'enabled=%s active=%s\n' \
    "$(systemctl is-enabled bluetooth.service 2>/dev/null | head -n 1 || echo unknown)" \
    "$(systemctl is-active bluetooth.service 2>/dev/null | head -n 1 || echo unknown)"
}

hardening_bluetooth_is_locked_down() {
  local en
  en="$(systemctl is-enabled bluetooth.service 2>/dev/null || true)"
  [[ "${en}" == masked || "${en}" == disabled ]]
}

hardening_wired_only_complete() {
  hardening_bluetooth_is_locked_down && hardening_wifi_radio_off
}

hardening_print_wired_only_status() {
  theme_section "Wired-only (Bluetooth / Wi-Fi)"
  if hardening_nmcli_available; then
    theme_meta_line "nmcli radio:"
    hardening_print_nmcli_radios
    echo
    theme_meta_line "nmcli devices:"
    hardening_print_nmcli_devices
  fi
  echo
  if hardening_bluetooth_is_locked_down; then
    ok "Bluetooth: $(hardening_bluetooth_unit_state | tr '\n' ' ')"
  else
    warn "Bluetooth: $(hardening_bluetooth_unit_state | tr '\n' ' ')"
  fi
  if hardening_wifi_radio_off; then
    ok "Wi-Fi radio: disabled (nmcli)"
  else
    warn "Wi-Fi radio: still enabled (nmcli)"
  fi
  if hardening_wifi_rfkill_blocked; then
    ok "Wi-Fi rfkill: soft blocked"
  elif have rfkill; then
    info "Wi-Fi rfkill: not soft blocked"
  fi
  if hardening_wired_ethernet_connected; then
    ok "Ethernet: connected (wired path OK)"
  else
    warn "Ethernet: no connected wired link detected — verify before disabling Wi-Fi"
  fi
}

hardening_disable_bluetooth() {
  local dry_run="${1:-0}"
  if hardening_bluetooth_is_locked_down && [[ "${dry_run}" == 0 ]]; then
    ok "Bluetooth: already masked/disabled (skipped)"
    return 0
  fi
  if (( dry_run )); then
    info "[dry-run] systemctl disable --now bluetooth.service; systemctl mask bluetooth.service"
    return 0
  fi
  if [[ "${EUID}" -eq 0 ]]; then
    systemctl disable --now bluetooth.service 2>/dev/null || true
    systemctl mask bluetooth.service 2>/dev/null || true
  else
    sudo systemctl disable --now bluetooth.service 2>/dev/null || true
    sudo systemctl mask bluetooth.service 2>/dev/null || true
  fi
  ok "Bluetooth: disabled and masked"
}

hardening_disable_wifi() {
  local dry_run="${1:-0}"
  if ! hardening_nmcli_available; then
    warn "nmcli not available — skipping Wi-Fi radio off"
    return 1
  fi
  if hardening_wifi_radio_off && [[ "${dry_run}" == 0 ]]; then
    ok "Wi-Fi radio: already disabled (skipped)"
    return 0
  fi
  if (( dry_run )); then
    info "[dry-run] nmcli radio wifi off; rfkill block wifi"
    return 0
  fi
  nmcli radio wifi off 2>/dev/null || warn "nmcli radio wifi off failed"
  if have rfkill; then
    if [[ "${EUID}" -eq 0 ]]; then
      rfkill block wifi 2>/dev/null || true
    else
      sudo rfkill block wifi 2>/dev/null || true
    fi
  fi
  ok "Wi-Fi: radio off + rfkill block"
}

hardening_apply_wired_only() {
  local dry_run="${1:-0}"
  hardening_disable_bluetooth "${dry_run}"
  hardening_disable_wifi "${dry_run}"
}

# ---------- Listening surface reduction (Round 2 follow-up) ----------
hardening_mariadb_dropin() {
  printf '/etc/my.cnf.d/90-fedora-toolkit-bind-localhost.cnf\n'
}

hardening_resolved_dropin() {
  printf '/etc/systemd/resolved.conf.d/90-fedora-toolkit-no-llmnr.conf\n'
}

hardening_mariadb_installed() {
  hardening_package_installed mariadb-server || hardening_package_installed MariaDB-server \
    || systemctl cat mariadb.service >/dev/null 2>&1
}

hardening_ss_listening() { network_ss_listening; }
hardening_mariadb_listens_public() { network_mariadb_listens_public; }
hardening_listening_has_avahi() { network_listening_has_avahi; }
hardening_listening_has_llmnr() { network_listening_has_llmnr; }
hardening_listening_has_cups() { network_listening_has_cups; }

hardening_mariadb_bound_localhost() {
  hardening_mariadb_installed || return 1
  if ! hardening_ss_listening | grep -qE ':3306'; then
    return 0
  fi
  hardening_mariadb_listens_public && return 1
  hardening_ss_listening | grep -E ':3306' | grep -q '127.0.0.1:3306'
}

hardening_resolved_llmnr_disabled() {
  local dropin
  dropin="$(hardening_resolved_dropin)"
  [[ -f "${dropin}" ]] && grep -qE '^LLMNR=no' "${dropin}" 2>/dev/null
}

hardening_write_root_file() {
  local dest="$1"
  local content="$2"
  local dry_run="${3:-0}"
  if (( dry_run )); then
    info "[dry-run] would write: ${dest}"
    printf '%s\n' "${content}" | sed 's/^/    /'
    return 0
  fi
  hardening_firewall_run_root mkdir -p "$(dirname "${dest}")"
  hardening_firewall_run_root tee "${dest}" >/dev/null <<< "${content}"
}

hardening_bind_mariadb_localhost() {
  local dry_run="${1:-0}"
  local dropin
  dropin="$(hardening_mariadb_dropin)"

  if ! hardening_mariadb_installed; then
    info "MariaDB: not installed (skipped)"
    return 0
  fi

  if hardening_mariadb_bound_localhost && [[ "${dry_run}" == 0 ]]; then
    ok "MariaDB: already bound to localhost only (skipped)"
    return 0
  fi

  info "Binding MariaDB to 127.0.0.1 only..."
  hardening_write_root_file "${dropin}" "# Managed by fedora-linux-scripts listening hardening
[mysqld]
bind-address = 127.0.0.1
" "${dry_run}"

  if (( dry_run )); then
    info "[dry-run] systemctl restart mariadb"
    return 0
  fi

  hardening_firewall_run_root systemctl restart mariadb.service 2>/dev/null \
    || hardening_firewall_run_root systemctl restart mariadb 2>/dev/null \
    || warn "MariaDB restart failed — check journalctl -u mariadb"
  sleep 1
  if hardening_mariadb_bound_localhost; then
    ok "MariaDB: listening on 127.0.0.1 only"
  elif hardening_mariadb_listens_public; then
    warn "MariaDB: still listening on all interfaces — check ${dropin} and other my.cnf snippets"
  else
    ok "MariaDB: no public 3306 listener detected"
  fi
}

hardening_disable_llmnr() {
  local dry_run="${1:-0}"
  local dropin
  dropin="$(hardening_resolved_dropin)"

  if hardening_resolved_llmnr_disabled && [[ "${dry_run}" == 0 ]]; then
    ok "LLMNR/mDNS (systemd-resolved): already disabled (skipped)"
    return 0
  fi

  info "Disabling LLMNR and MulticastDNS in systemd-resolved..."
  hardening_write_root_file "${dropin}" "# Managed by fedora-linux-scripts listening hardening
[Resolve]
LLMNR=no
MulticastDNS=no
" "${dry_run}"

  if (( dry_run )); then
    info "[dry-run] systemctl restart systemd-resolved"
    return 0
  fi

  hardening_firewall_run_root systemctl restart systemd-resolved 2>/dev/null || true
  ok "systemd-resolved: LLMNR=no MulticastDNS=no"
}

hardening_disable_system_unit() {
  local unit="$1"
  local dry_run="${2:-0}"
  local mask="${3:-0}"

  if ! hardening_unit_exists "${unit}"; then
    return 0
  fi
  if hardening_unit_is_disabled "${unit}" && [[ "${dry_run}" == 0 ]]; then
    ok "${unit}: already disabled (skipped)"
    return 0
  fi
  if (( dry_run )); then
    if (( mask )); then
      info "[dry-run] systemctl disable --now ${unit}; systemctl mask ${unit}"
    else
      info "[dry-run] systemctl disable --now ${unit}"
    fi
    return 0
  fi
  hardening_firewall_run_root systemctl disable --now "${unit}" 2>/dev/null || true
  if (( mask )); then
    hardening_firewall_run_root systemctl mask "${unit}" 2>/dev/null || true
  fi
  ok "${unit}: disabled"
}

hardening_disable_avahi() {
  local dry_run="${1:-0}"
  hardening_disable_system_unit avahi-daemon.service "${dry_run}" 0
  hardening_disable_system_unit avahi-daemon.socket "${dry_run}" 0
}

hardening_disable_cups() {
  local dry_run="${1:-0}"
  hardening_disable_system_unit cups.service "${dry_run}" 0
  hardening_disable_system_unit cups.socket "${dry_run}" 0
}

hardening_print_listening_audit() {
  local line
  theme_section "Listening port audit"
  hardening_print_listening_services
  echo
  if hardening_mariadb_installed; then
    if hardening_mariadb_listens_public; then
      warn "MariaDB: listening on all interfaces (0.0.0.0/[::]:3306) — bind to 127.0.0.1"
    elif hardening_mariadb_bound_localhost; then
      ok "MariaDB: localhost only (127.0.0.1:3306 or socket)"
    else
      info "MariaDB: no tcp:3306 listener (may use socket only)"
    fi
  fi
  if hardening_listening_has_avahi; then
    warn "Avahi: still listening on UDP 5353 (mDNS)"
  elif hardening_unit_is_disabled avahi-daemon.service 2>/dev/null; then
    ok "Avahi: service disabled"
  else
    info "Avahi: not detected on 5353"
  fi
  if hardening_listening_has_llmnr; then
    if hardening_resolved_llmnr_disabled; then
      info "LLMNR: port 5355 still open — may clear after restart/logout"
    else
      warn "LLMNR: systemd-resolved on UDP 5355 — disable with LLMNR=no"
    fi
  else
    ok "LLMNR: UDP 5355 not listening"
  fi
  if hardening_ss_listening | grep -qE '0\.0\.0\.0:22|\[::\]:22|\*:22'; then
    ok "SSH: listening (expected on 0.0.0.0:22 or [::]:22)"
  fi
  theme_meta_line "Target: ssh public · mariadb/chronyd/resolved on localhost only"
}

hardening_print_listening_status() {
  theme_section "Listening hardening status"
  if hardening_mariadb_installed; then
    if hardening_mariadb_bound_localhost; then
      ok "MariaDB bind: localhost only"
    else
      warn "MariaDB bind: not localhost-only yet"
    fi
  fi
  if hardening_unit_is_disabled avahi-daemon.service 2>/dev/null || ! hardening_unit_exists avahi-daemon.service; then
    ok "Avahi: disabled or not installed"
  else
    warn "Avahi: still enabled"
  fi
  if hardening_unit_is_disabled cups.service 2>/dev/null || ! hardening_unit_exists cups.service; then
    ok "CUPS: disabled or not installed"
  else
    info "CUPS: still enabled (disable if no printer)"
  fi
  hardening_print_wired_only_status
  echo
  if hardening_resolved_llmnr_disabled; then
    ok "systemd-resolved: LLMNR=no"
  else
    warn "systemd-resolved: LLMNR not disabled"
  fi
}

hardening_apply_listening_hardening() {
  local dry_run="${1:-0}"
  local skip_wifi="${2:-0}"
  info "Step 1/5 — MariaDB localhost bind..."
  hardening_bind_mariadb_localhost "${dry_run}"
  echo
  info "Step 2/5 — Disable Avahi (mDNS)..."
  hardening_disable_avahi "${dry_run}"
  echo
  info "Step 3/5 — Disable CUPS (printing)..."
  hardening_disable_cups "${dry_run}"
  echo
  info "Step 4/5 — Wired only (Bluetooth + Wi-Fi)..."
  if (( skip_wifi )); then
    hardening_disable_bluetooth "${dry_run}"
  else
    hardening_apply_wired_only "${dry_run}"
  fi
  echo
  info "Step 5/5 — Disable LLMNR (systemd-resolved)..."
  hardening_disable_llmnr "${dry_run}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
