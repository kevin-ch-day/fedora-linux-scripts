#!/usr/bin/env bash
# lib/security_audit.sh — read-only host security audit helpers
# Version: 0.4.0
#
# Source after lib/common.sh. Does not modify system state.

if [[ -n "${FEDORA_SECURITY_AUDIT_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_SECURITY_AUDIT_SH_LOADED=1

_AUDIT_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_AUDIT_LIB_DIR}/common.sh"
# shellcheck source=health.sh
source "${_AUDIT_LIB_DIR}/health.sh"
# shellcheck source=logging.sh
source "${_AUDIT_LIB_DIR}/logging.sh"
# shellcheck source=baseline.sh
source "${_AUDIT_LIB_DIR}/baseline.sh"
# shellcheck source=hardening.sh
source "${_AUDIT_LIB_DIR}/hardening.sh"
# shellcheck source=host_context.sh
source "${_AUDIT_LIB_DIR}/host_context.sh"

# severity|id|message|remediation
declare -a SECURITY_AUDIT_FINDINGS=()
declare -a SECURITY_AUDIT_ACTION_PLAN=()

security_audit_systemd_active() {
  local unit="$1" st
  st="$(systemctl is-active "${unit}" 2>/dev/null || true)"
  st="${st%%$'\n'*}"
  [[ -n "${st}" ]] || st="unknown"
  printf '%s\n' "${st}"
}

security_audit_systemd_enabled() {
  local unit="$1" st
  st="$(systemctl is-enabled "${unit}" 2>/dev/null || true)"
  st="${st%%$'\n'*}"
  [[ -n "${st}" ]] || st="unknown"
  printf '%s\n' "${st}"
}

security_audit_root() {
  if [[ -n "${FEDORA_SECURITY_AUDIT_ROOT:-}" ]]; then
    printf '%s\n' "${FEDORA_SECURITY_AUDIT_ROOT}"
    return 0
  fi
  system_state_log_root security_audit
}

security_audit_session_dir() {
  local stamp="$1"
  printf '%s/%s\n' "$(security_audit_root)" "${stamp}"
}

security_audit_report_path() {
  local session_dir="$1"
  local stamp="$2"
  local slug
  slug="$(hardening_host_slug)"
  [[ -n "${slug}" ]] || slug="host"
  printf '%s/security_audit_%s_%s.txt\n' "${session_dir}" "${slug}" "${stamp}"
}

security_audit_findings_path() {
  local session_dir="$1"
  local stamp="$2"
  local slug
  slug="$(hardening_host_slug)"
  [[ -n "${slug}" ]] || slug="host"
  printf '%s/findings_%s_%s.txt\n' "${session_dir}" "${slug}" "${stamp}"
}

security_audit_latest_report_path() {
  local slug root
  slug="$(hardening_host_slug)"
  root="$(security_audit_root)"
  find "${root}" -type f -name "security_audit_${slug}_*.txt" 2>/dev/null \
    | sort | tail -n 1
}

security_audit_run() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@" 2>&1 || printf '[exit %s]\n' "$?"
  elif have sudo; then
    sudo "$@" 2>&1 || printf '[exit %s]\n' "$?"
  else
    "$@" 2>&1 || printf '[exit %s]\n' "$?"
  fi
}

security_audit_section() {
  echo
  echo "================================================================================"
  echo "$1"
  echo "================================================================================"
}

security_audit_latest_findings_path() {
  local slug root
  slug="$(hardening_host_slug)"
  root="$(security_audit_root)"
  find "${root}" -type f -name "findings_${slug}_*.txt" 2>/dev/null \
    | sort | tail -n 1
}

security_audit_finding_has() {
  local want_id="$1" f id
  for f in "${SECURITY_AUDIT_FINDINGS[@]}"; do
    id="${f#*|}"; id="${id%%|*}"
    [[ "${id}" == "${want_id}" ]] && return 0
  done
  return 1
}

security_audit_finding_has_severity() {
  local want_sev="$1" f sev
  for f in "${SECURITY_AUDIT_FINDINGS[@]}"; do
    sev="${f%%|*}"
    [[ "${sev}" == "${want_sev}" ]] && return 0
  done
  return 1
}

security_audit_finding_severity() {
  local want_id="$1" f id sev
  for f in "${SECURITY_AUDIT_FINDINGS[@]}"; do
    sev="${f%%|*}"
    id="${f#*|}"; id="${id%%|*}"
    if [[ "${id}" == "${want_id}" ]]; then
      printf '%s\n' "${sev}"
      return 0
    fi
  done
  return 1
}

security_audit_add_finding() {
  local sev="$1" id="$2" msg="$3" fix="${4:-}"
  security_audit_finding_has "${id}" && return 0
  SECURITY_AUDIT_FINDINGS+=("${sev}|${id}|${msg}|${fix}")
}

security_audit_finding_count() {
  local sev="$1" f
  local n=0
  for f in "${SECURITY_AUDIT_FINDINGS[@]}"; do
    [[ "${f%%|*}" == "${sev}" ]] && n=$((n + 1))
  done
  printf '%s\n' "${n}"
}

security_audit_sshd_effective() {
  local key="$1"
  hardening_sshd_effective_key "${key}" 0 2>/dev/null | head -n 1
}

security_audit_public_listeners() {
  network_public_listeners
}

security_audit_analyze() {
  local zone strict_zone def_zone f sev id msg fix line research=0
  SECURITY_AUDIT_FINDINGS=()
  SECURITY_AUDIT_ACTION_PLAN=()
  zone="$(hardening_firewall_strict_zone_name)"
  strict_zone="${zone}"
  def_zone="$(hardening_firewall_default_zone 2>/dev/null | head -n 1 | tr -d '[:space:]')"
  hardening_is_research_host && research=1

  if [[ "$(users_session_kind)" == ssh ]] && host_context_is_research_host; then
    security_audit_add_finding INFO ssh-session \
      "Audit running over SSH from $(users_ssh_client_address 2>/dev/null || echo unknown)" \
      ""
  fi

  if host_context_is_research_host && [[ "$(users_count_wheel_accounts)" -gt 1 ]]; then
    security_audit_add_finding WARN multiple-wheel \
      "Multiple wheel accounts: $(users_detect_wheel 2>/dev/null || echo unknown)" \
      "./system/hardening_round1.sh --yes --allow-users wheel"
  fi

  if ! system_state_sudo_passwordless && system_state_sudo_available; then
    security_audit_add_finding INFO sudo-password \
      "sudo requires a password — run remediation commands in an interactive shell" \
      ""
  fi

  # --- SELinux / core ---
  if [[ "$(getenforce 2>/dev/null)" != "Enforcing" ]]; then
    security_audit_add_finding CRITICAL selinux-not-enforcing \
      "SELinux is not enforcing ($(getenforce 2>/dev/null || echo unknown))" \
      "./system/hardening_round1.sh --yes"
  fi

  if ! hardening_round1_complete 2>/dev/null; then
    security_audit_add_finding WARN round1-incomplete \
      "Round 1 hardening incomplete on this host" \
      "./system/hardening_round1.sh --status"
  else
    security_audit_add_finding OK round1-complete \
      "Round 1 hardening complete" ""
  fi

  # --- Firewall ---
  if ! have firewall-cmd; then
    security_audit_add_finding CRITICAL firewalld-missing \
      "firewalld/firewall-cmd not available" \
      "sudo systemctl enable --now firewalld"
  elif [[ "$(systemctl is-active firewalld 2>/dev/null)" != "active" ]]; then
    security_audit_add_finding CRITICAL firewalld-inactive \
      "firewalld is not active" \
      "sudo systemctl enable --now firewalld"
  elif [[ "${def_zone}" == "unknown" || -z "${def_zone}" ]] && network_firewall_active; then
    security_audit_add_finding WARN firewall-sudo-blind \
      "firewalld running but zone info unavailable (sudo likely required for full audit)" \
      "sudo ./system/security_audit.sh --findings"
  elif hardening_round2_firewall_is_strict "${def_zone}" 2>/dev/null; then
    security_audit_add_finding OK firewall-strict-default \
      "Default firewall zone (${def_zone}) is strict — ssh only" ""
  elif hardening_round2_firewall_is_strict "${strict_zone}" 2>/dev/null \
    && [[ "${def_zone}" != "${strict_zone}" ]]; then
    security_audit_add_finding WARN firewall-zone-split \
      "Strict zone ${strict_zone} exists but default zone is ${def_zone:-unknown}" \
      "./system/hardening_firewall_strict.sh --yes"
  elif hardening_firewall_zone_has_wide_ports FedoraWorkstation 2>/dev/null; then
    security_audit_add_finding CRITICAL firewall-workstation-ports \
      "FedoraWorkstation zone still has wide port range 1025-65535" \
      "./system/hardening_firewall_strict.sh --yes"
  elif [[ "${def_zone}" == "FedoraWorkstation" || "${def_zone}" == "workstation" ]]; then
    if (( research )); then
      security_audit_add_finding WARN firewall-workstation-zone \
        "Default zone is ${def_zone} (workstation profile)" \
        "./system/hardening_firewall_strict.sh --yes"
    else
      security_audit_add_finding INFO firewall-workstation-zone \
        "Default zone is ${def_zone} (OK for desktop — use FEDORA_HARDENING_PROFILE=research to enforce strict)" \
        "./system/hardening_firewall_strict.sh --status"
    fi
  else
    security_audit_add_finding WARN firewall-review \
      "Firewall profile needs review (default: ${def_zone:-unknown})" \
      "./system/hardening_firewall_strict.sh --status"
  fi

  # --- SSH ---
  if [[ "$(security_audit_systemd_active sshd)" != "active" ]]; then
    if (( research )); then
      security_audit_add_finding WARN sshd-inactive \
        "sshd is not active" \
        "sudo systemctl enable --now sshd"
    else
      security_audit_add_finding INFO sshd-inactive \
        "sshd is not active (OK if this host is not used for remote SSH)" \
        "sudo systemctl enable --now sshd"
    fi
  fi
  if [[ "$(security_audit_sshd_effective permitrootlogin)" == "yes" ]]; then
    security_audit_add_finding CRITICAL ssh-root-login \
      "SSH PermitRootLogin is yes" \
      "./system/hardening_round1.sh --yes"
  fi
  if [[ -z "$(security_audit_sshd_effective allowusers)" ]]; then
    security_audit_add_finding WARN ssh-no-allowusers \
      "SSH AllowUsers not set (any user may attempt login)" \
      "./system/hardening_round1.sh --yes --allow-users wheel"
  fi
  if [[ "$(security_audit_sshd_effective x11forwarding)" == "yes" ]]; then
    security_audit_add_finding WARN ssh-x11 \
      "SSH X11Forwarding is enabled" \
      "./system/hardening_round1.sh --yes --force"
  fi

  # --- Listening / MariaDB ---
  if hardening_mariadb_installed 2>/dev/null; then
    if hardening_mariadb_listens_public 2>/dev/null; then
      security_audit_add_finding CRITICAL mariadb-public \
        "MariaDB listening on 0.0.0.0/[::]:3306 — bind to localhost" \
        "./system/hardening_listening.sh --yes --mariadb-only"
    else
      security_audit_add_finding OK mariadb-local \
        "MariaDB not listening on all interfaces" ""
    fi
  fi

  if hardening_listening_has_avahi 2>/dev/null; then
    if (( research )); then
      security_audit_add_finding WARN avahi-mdns \
        "Avahi/mDNS listening (UDP 5353)" \
        "./system/hardening_listening.sh --yes"
    else
      security_audit_add_finding INFO avahi-mdns \
        "Avahi/mDNS listening (UDP 5353 — expected on desktop)" \
        ""
    fi
  fi
  if hardening_listening_has_llmnr 2>/dev/null; then
    if (( research )); then
      security_audit_add_finding WARN llmnr \
        "LLMNR listening (UDP 5355 via systemd-resolved)" \
        "./system/hardening_listening.sh --yes"
    else
      security_audit_add_finding INFO llmnr \
        "LLMNR listening (UDP 5355 — disable on research hosts)" \
        "./system/hardening_listening.sh --yes"
    fi
  fi
  if hardening_listening_has_cups 2>/dev/null; then
    if (( research )); then
      security_audit_add_finding WARN cups-listener \
        "CUPS listening (TCP 631)" \
        "./system/hardening_listening.sh --yes"
    else
      security_audit_add_finding INFO cups-listener \
        "CUPS listening (TCP 631 — expected if printing is used)" \
        ""
    fi
  fi

  if (( research )); then
    if ! hardening_bluetooth_is_locked_down 2>/dev/null \
      && hardening_unit_exists bluetooth.service 2>/dev/null; then
      security_audit_add_finding INFO bluetooth-enabled \
        "Bluetooth service not masked/disabled" \
        "./system/hardening_wired_only.sh --yes"
    fi
    if ! hardening_wifi_radio_off 2>/dev/null && hardening_nmcli_available; then
      security_audit_add_finding INFO wifi-enabled \
        "Wi-Fi radio enabled ($(nmcli radio wifi 2>/dev/null || echo unknown))" \
        "./system/hardening_wired_only.sh --yes"
    fi
  fi

  # Unexpected public listeners (SSH :22 allowed on research hosts)
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    security_audit_add_finding WARN public-listener \
      "Unexpected public listener: ${line}" \
      "Review ss -tulpen; ./system/hardening_listening.sh --status"
  done < <(network_unexpected_public_listeners | head -n 8)

  if [[ "$(system_state_failed_units_count)" -gt 0 ]]; then
    security_audit_add_finding WARN failed-systemd-units \
      "$(system_state_failed_units_count) failed systemd unit(s)" \
      "systemctl --failed"
  fi

  local root_pct
  root_pct="$(health_root_disk_pct 2>/dev/null || echo 0)"
  if [[ "${root_pct}" =~ ^[0-9]+$ ]] && (( root_pct >= 90 )); then
    security_audit_add_finding WARN disk-root-full \
      "Root filesystem ${root_pct}% full" \
      "df -h / ; ./system/cleanup.sh"
  fi

  # Round 2 service candidates still enabled (research hosts only)
  if (( research )); then
    while IFS='|' read -r unit reason tier; do
      [[ "${tier}" == safe ]] || continue
      [[ -n "${unit}" ]] || continue
      case "${unit}" in
        bluetooth) security_audit_finding_has bluetooth-enabled && continue ;;
      esac
      hardening_unit_exists "${unit}" || continue
      hardening_unit_is_disabled "${unit}" && continue
      if hardening_round2_service_needs_disable "${unit}" 2>/dev/null; then
        security_audit_add_finding INFO "svc-${unit}" \
          "${unit} enabled/active — ${reason}" \
          "./system/hardening_listening.sh --yes  or  ./system/hardening_round2.sh --yes --services-only"
      fi
    done < <(hardening_round2_service_units)
  fi

  # DNF / repos
  if have dnf && ! baseline_dnf_check_ok 2>/dev/null; then
    security_audit_add_finding WARN dnf-check-failed \
      "dnf check failed (repo permissions or config)" \
      "sudo ./fedora.sh --fix-repos"
  fi

  if ! findmnt -n /data >/dev/null 2>&1; then
    security_audit_add_finding INFO data-not-mounted \
      "/data not mounted (optional for this host)" ""
  fi

  security_audit_build_action_plan
}

security_audit_plan_add() {
  local cmd="$1" existing
  [[ -n "${cmd}" ]] || return 0
  for existing in "${SECURITY_AUDIT_ACTION_PLAN[@]}"; do
    [[ "${existing}" == "${cmd}" ]] && return 0
  done
  SECURITY_AUDIT_ACTION_PLAN+=("${cmd}")
}

security_audit_build_action_plan() {
  SECURITY_AUDIT_ACTION_PLAN=()

  security_audit_finding_has selinux-not-enforcing \
    && security_audit_plan_add "./system/hardening_round1.sh --yes"
  security_audit_finding_has round1-incomplete \
    && security_audit_plan_add "./system/hardening_round1.sh --status"
  security_audit_finding_has firewalld-missing \
    && security_audit_plan_add "sudo systemctl enable --now firewalld"
  security_audit_finding_has firewalld-inactive \
    && security_audit_plan_add "sudo systemctl enable --now firewalld"
  security_audit_finding_has firewall-workstation-ports \
    && security_audit_plan_add "./system/hardening_firewall_strict.sh --yes"
  if [[ "$(security_audit_finding_severity firewall-workstation-zone 2>/dev/null || true)" == WARN ]]; then
    security_audit_plan_add "./system/hardening_firewall_strict.sh --yes"
  fi
  security_audit_finding_has firewall-zone-split \
    && security_audit_plan_add "./system/hardening_firewall_strict.sh --yes"
  security_audit_finding_has firewall-review \
    && security_audit_plan_add "./system/hardening_firewall_strict.sh --status"
  security_audit_finding_has mariadb-public \
    && security_audit_plan_add "./system/hardening_listening.sh --yes --mariadb-only"
  if security_audit_finding_has avahi-mdns \
    || security_audit_finding_has llmnr \
    || security_audit_finding_has cups-listener \
    || security_audit_finding_has public-listener; then
    security_audit_plan_add "./system/hardening_listening.sh --yes"
  fi
  if security_audit_finding_has bluetooth-enabled \
    || security_audit_finding_has wifi-enabled; then
    security_audit_plan_add "./system/hardening_wired_only.sh --yes"
  fi
  if security_audit_finding_has ssh-root-login \
    || security_audit_finding_has ssh-no-allowusers \
    || security_audit_finding_has ssh-x11; then
    security_audit_plan_add "./system/hardening_round1.sh --yes"
  fi
  security_audit_finding_has dnf-check-failed \
    && security_audit_plan_add "sudo ./fedora.sh --fix-repos"
  if [[ ${#SECURITY_AUDIT_ACTION_PLAN[@]} -gt 0 ]]; then
    security_audit_plan_add "./system/security_audit.sh --findings --compare"
  fi
}

security_audit_context_path() {
  local session_dir="$1"
  local stamp="$2"
  local slug
  slug="$(host_context_host_slug)"
  printf '%s/context_%s_%s.txt\n' "${session_dir}" "${slug}" "${stamp}"
}

security_audit_latest_context_path() {
  local slug root
  slug="$(host_context_host_slug)"
  root="$(security_audit_root)"
  find "${root}" -type f -name "context_${slug}_*.txt" 2>/dev/null | sort | tail -n 1
}

security_audit_write_context_file() {
  local path="$1"
  {
    echo "# Host context — $(health_hostname) — $(date -Iseconds)"
    host_context_snapshot
  } > "${path}"
}

security_audit_write_findings_file() {
  local path="$1"
  local f
  {
    echo "# Security audit findings — $(health_hostname) — $(date -Iseconds)"
    echo "# format: severity|id|message|remediation"
    echo
    for f in "${SECURITY_AUDIT_FINDINGS[@]}"; do
      echo "${f}"
    done
  } > "${path}"
}

security_audit_print_findings_themed() {
  local sev id msg fix printed=0
  local -a order=(CRITICAL WARN INFO OK)
  local s f

  theme_section "Smart findings (prioritized)"
  for s in "${order[@]}"; do
    for f in "${SECURITY_AUDIT_FINDINGS[@]}"; do
      sev="${f%%|*}"
      [[ "${sev}" == "${s}" ]] || continue
      id="${f#*|}"; id="${id%%|*}"
      msg="${f#*|}"; msg="${msg#*|}"; msg="${msg%%|*}"
      fix="${f##*|}"
      printed=1
      case "${sev}" in
        CRITICAL) theme_msg_err "${msg}" ;;
        WARN) theme_msg_warn "${msg}" ;;
        INFO) theme_msg_info "${msg}" ;;
        OK) theme_msg_ok "${msg}" ;;
      esac
      [[ -n "${fix}" ]] && theme_meta_line "  → ${fix}"
    done
  done
  if (( printed == 0 )); then
    theme_msg_info "No findings recorded"
  fi
  echo
  theme_meta_line "Critical: $(security_audit_finding_count CRITICAL) · Warn: $(security_audit_finding_count WARN) · Info: $(security_audit_finding_count INFO) · OK: $(security_audit_finding_count OK)"
}

security_audit_print_action_plan() {
  local i=1 cmd
  theme_section "Recommended action plan (ordered)"
  if [[ ${#SECURITY_AUDIT_ACTION_PLAN[@]} -eq 0 ]]; then
    theme_msg_ok "No remediation steps — host looks good for its profile"
    theme_meta_line "Profile: $(hardening_research_profile_label | tr -d '\n')"
    return 0
  fi
  theme_meta_line "Profile: $(hardening_research_profile_label | tr -d '\n')"
  for cmd in "${SECURITY_AUDIT_ACTION_PLAN[@]}"; do
    printf '  %s) %s\n' "${i}" "${cmd}"
    i=$((i + 1))
  done
}

security_audit_print_findings_plain() {
  local sev id msg fix
  security_audit_section "18) SMART FINDINGS (prioritized)"
  echo "severity | id | message | remediation"
  echo "---------|----|---------|--------------"
  local f
  for f in "${SECURITY_AUDIT_FINDINGS[@]}"; do
    sev="${f%%|*}"
    id="${f#*|}"; id="${id%%|*}"
    msg="${f#*|}"; msg="${msg#*|}"; msg="${msg%%|*}"
    fix="${f##*|}"
    printf '%s | %s | %s | %s\n' "${sev}" "${id}" "${msg}" "${fix}"
  done
  echo
  echo "Counts: CRITICAL=$(security_audit_finding_count CRITICAL) WARN=$(security_audit_finding_count WARN) INFO=$(security_audit_finding_count INFO) OK=$(security_audit_finding_count OK)"
}

security_audit_print_summary_flags() {
  local zone
  zone="$(hardening_firewall_strict_zone_name)"
  echo "Hostname          : $(health_hostname)"
  echo "OS                : $(hardening_os_label | tr -d '\n')"
  echo "Hardening profile : $(host_context_research_label | tr -d '\n')"
  echo "Session           : $(users_session_label | tr -d '\n')"
  echo "UEFI boot         : $(baseline_uefi_label 2>/dev/null || { [[ -d /sys/firmware/efi ]] && echo yes || echo no; })"
  echo "SELinux           : $(getenforce 2>/dev/null || echo unknown)"
  echo "firewalld         : $(security_audit_systemd_active firewalld)"
  echo "sshd              : $(security_audit_systemd_active sshd)"
  echo "mariadb           : $(security_audit_systemd_active mariadb)"
  echo "fstrim.timer      : $(security_audit_systemd_enabled fstrim.timer)"
  echo "Default FW zone   : $(hardening_firewall_default_zone 2>/dev/null | head -n 1 || echo unknown)"
  echo "Strict FW zone    : ${zone}"
  if hardening_round2_firewall_is_strict "$(hardening_firewall_default_zone 2>/dev/null | tr -d '[:space:]' || true)" 2>/dev/null; then
    echo "FW strict profile : yes (default zone ssh-only)"
  elif hardening_round2_firewall_is_strict "${zone}" 2>/dev/null; then
    echo "FW strict profile : partial (${zone} ok; default may differ)"
  else
    echo "FW strict profile : no"
  fi
  if findmnt -n /data >/dev/null 2>&1; then
    echo "Data mount        : $(findmnt -no SOURCE,FSTYPE,OPTIONS /data 2>/dev/null)"
  else
    echo "Data mount        : (not mounted)"
  fi
  echo "Swap used         : $(free -h | awk '/Swap:/ {print $3}')"
  if hardening_mariadb_installed 2>/dev/null; then
    if hardening_mariadb_listens_public 2>/dev/null; then
      echo "MariaDB bind      : CRITICAL — 0.0.0.0/[::]:3306"
    elif hardening_mariadb_bound_localhost 2>/dev/null; then
      echo "MariaDB bind      : OK — localhost only"
    else
      echo "MariaDB bind      : review"
    fi
  else
    echo "MariaDB bind      : n/a"
  fi
  if hardening_listening_has_avahi 2>/dev/null; then
    echo "Avahi/mDNS        : WARN — UDP 5353"
  else
    echo "Avahi/mDNS        : OK"
  fi
  if hardening_listening_has_llmnr 2>/dev/null; then
    echo "LLMNR             : WARN — UDP 5355"
  else
    echo "LLMNR             : OK"
  fi
  if hardening_listening_has_cups 2>/dev/null; then
    echo "CUPS (631)        : WARN — listening"
  else
    echo "CUPS (631)        : OK"
  fi
  if hardening_bluetooth_is_locked_down 2>/dev/null; then
    echo "Bluetooth         : OK — masked/disabled"
  else
    echo "Bluetooth         : review"
  fi
  if hardening_wifi_radio_off 2>/dev/null; then
    echo "Wi-Fi radio       : OK — disabled"
  else
    echo "Wi-Fi radio       : review"
  fi
  echo "Findings          : CRITICAL=$(security_audit_finding_count CRITICAL) WARN=$(security_audit_finding_count WARN) INFO=$(security_audit_finding_count INFO)"
}

security_audit_compare_with_previous() {
  local prev="$1"
  local key
  if [[ ! -f "${prev}" ]]; then
    info "No previous audit to compare"
    return 0
  fi
  theme_section "Changes since previous audit"
  theme_meta_line "Previous: ${prev}"
  while IFS= read -r key; do
    [[ -n "${key}" ]] || continue
    local old new
    old="$(grep -F "${key}" "${prev}" 2>/dev/null | head -n 1 | sed 's/^[^:]*:[[:space:]]*//' || true)"
    new="$(grep -F "${key}" <<< "$(security_audit_print_summary_flags)" 2>/dev/null | head -n 1 | sed 's/^[^:]*:[[:space:]]*//' || true)"
    if [[ -z "${old}" ]]; then
      continue
    fi
    if [[ "${old}" != "${new}" ]]; then
      warn "${key} changed: ${old} → ${new}"
    fi
  done <<'EOF'
Default FW zone
FW strict profile
MariaDB bind
Avahi/mDNS
LLMNR
CUPS (631)
Bluetooth
Wi-Fi radio
SELinux
Hardening profile
EOF
}

security_audit_compare_findings_with_previous() {
  local prev_findings="$1"
  local line sev id msg old_sev
  declare -A prev_ids=()
  declare -A curr_ids=()

  if [[ ! -f "${prev_findings}" ]]; then
    return 0
  fi

  theme_section "Finding changes since previous audit"
  theme_meta_line "Previous findings: ${prev_findings}"

  while IFS= read -r line; do
    [[ "${line}" =~ ^# || -z "${line}" ]] && continue
    id="${line#*|}"; id="${id%%|*}"
    prev_ids["${id}"]="${line%%|*}"
  done < "${prev_findings}"

  for line in "${SECURITY_AUDIT_FINDINGS[@]}"; do
    id="${line#*|}"; id="${id%%|*}"
    curr_ids["${id}"]="${line%%|*}"
  done

  for id in "${!curr_ids[@]}"; do
    sev="${curr_ids[${id}]}"
    old_sev="${prev_ids[${id}]:-}"
    if [[ -z "${old_sev}" && "${sev}" != OK ]]; then
      warn "New finding: [${sev}] ${id}"
    elif [[ -n "${old_sev}" && "${old_sev}" != "${sev}" ]]; then
      warn "Severity changed: ${id} ${old_sev} → ${sev}"
    elif [[ -n "${old_sev}" && "${sev}" == OK && "${old_sev}" != OK ]]; then
      ok "Resolved: ${id} (was ${old_sev})"
    fi
  done

  for id in "${!prev_ids[@]}"; do
    [[ -n "${curr_ids[${id}]:-}" ]] && continue
    old_sev="${prev_ids[${id}]}"
    [[ "${old_sev}" == OK ]] && continue
    ok "Removed finding: ${id} (was ${old_sev})"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
