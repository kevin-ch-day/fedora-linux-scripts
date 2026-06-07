#!/usr/bin/env bash
# security_audit.sh — read-only host security audit (no changes)
# Version: 0.4.0
#
# Full report + smart findings with remediation hints.
# Report → /data/logs/security_audit/<stamp>/
#
# Run:
#   ./system/security_audit.sh
#   ./system/security_audit.sh --summary
#   ./system/security_audit.sh --findings
#   ./system/security_audit.sh --plan
#   ./system/security_audit.sh --quick --compare

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${_SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/security_audit.sh
source "${FEDORA_ROOT}/lib/security_audit.sh"
# shellcheck source=../lib/theme.sh
source "${FEDORA_ROOT}/lib/theme.sh"
theme_init

CONTEXT_ONLY=0
SUMMARY_ONLY=0
FINDINGS_ONLY=0
PLAN_ONLY=0
QUICK=0
COMPARE=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Read-only security audit — does not change system settings.

Modes:
  (default)    Full 17-section report + smart findings (section 18)
  --context    Machine-readable host context snapshot (key=value)
  --summary    Quick terminal summary + prioritized findings (no full report)
  --findings   Live findings + remediation only (fastest)
  --plan       Ordered remediation plan from current findings (fastest)
  --quick      Skip slower sections (dnf updates, full journals, crontabs)
  --compare    After run, diff key flags vs previous audit on this host

Output:
  /data/logs/security_audit/<stamp>/security_audit_<host>_<stamp>.txt
  /data/logs/security_audit/<stamp>/findings_<host>_<stamp>.txt

Also: ./system/system.sh security-audit
      System menu → [8] OS hardening → [9]

Toolkit root: ${FEDORA_ROOT}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --context) CONTEXT_ONLY=1; shift ;;
    --summary) SUMMARY_ONLY=1; shift ;;
    --findings) FINDINGS_ONLY=1; shift ;;
    --plan) PLAN_ONLY=1; shift ;;
    --quick) QUICK=1; shift ;;
    --compare) COMPARE=1; shift ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

host="$(health_hostname)"
strict_zone="$(hardening_firewall_strict_zone_name)"
prev_report="$(security_audit_latest_report_path 2>/dev/null || true)"
prev_findings="$(security_audit_latest_findings_path 2>/dev/null || true)"

if (( CONTEXT_ONLY )); then
  host_context_snapshot
  exit 0
fi

if (( FINDINGS_ONLY || SUMMARY_ONLY || PLAN_ONLY )); then
  theme_banner "Security audit — live analysis"
  hardening_print_host_banner_meta
  host_context_remediation_notes
  theme_rule '─'
  echo
  security_audit_analyze
  if (( PLAN_ONLY )); then
    security_audit_print_action_plan
    echo
    exit $(( $(security_audit_finding_count CRITICAL) > 0 ? 1 : 0 ))
  fi
  security_audit_print_findings_themed
  echo
  security_audit_print_action_plan
  echo
  theme_section "Summary flags"
  security_audit_print_summary_flags | sed 's/^/  /'
  echo
  if (( COMPARE )); then
    if [[ -n "${prev_report}" ]]; then
      security_audit_compare_with_previous "${prev_report}"
    else
      info "No previous audit on this host for comparison"
    fi
    if [[ -n "${prev_findings}" ]]; then
      echo
      security_audit_compare_findings_with_previous "${prev_findings}"
    fi
    prev_ctx="$(host_context_latest_snapshot_path 2>/dev/null || true)"
    if [[ -n "${prev_ctx}" ]]; then
      echo
      host_context_compare_snapshots "${prev_ctx}"
    fi
  fi
  if (( security_audit_finding_count CRITICAL > 0 )); then
    theme_summary_box "Audit analysis" \
      "Host:      ${host}" \
      "Critical:  $(security_audit_finding_count CRITICAL) item(s) need attention" \
      "Next:      run findings above, then ./system/security_audit.sh --compare"
    exit 1
  fi
  theme_summary_box "Audit analysis" \
    "Host:     ${host}" \
    "Critical: 0" \
    "Next:     ./system/security_audit.sh for full report"
  exit 0
fi

stamp="$(date +%Y%m%d_%H%M%S)"
session_dir="$(security_audit_session_dir "${stamp}")"
out="$(security_audit_report_path "${session_dir}" "${stamp}")"
findings_out="$(security_audit_findings_path "${session_dir}" "${stamp}")"
context_out="$(security_audit_context_path "${session_dir}" "${stamp}")"
prev_context="$(security_audit_latest_context_path 2>/dev/null || true)"

mkdir -p "${session_dir}"
security_audit_analyze

theme_banner "Security audit (read-only)"
hardening_print_host_banner_meta
theme_meta_line "Report: ${out}"
theme_meta_line "Findings: ${findings_out}"
theme_meta_line "Context: ${context_out}"
if (( QUICK )); then
  theme_meta_line "Mode: quick"
fi
theme_rule '─'
info "Collecting audit data (sudo for read-only commands)..."
echo

_run_audit() {
  security_audit_section "HOST SECURITY AUDIT"
  echo "Generated : $(date -Iseconds)"
  echo "Hostname  : ${host}"
  echo "Output    : ${out}"
  echo "Findings  : ${findings_out}"
  echo "Toolkit   : ${FEDORA_ROOT}"
  echo "Mode      : read-only (no changes)"

  security_audit_section "HOST CONTEXT (snapshot)"
  host_context_snapshot
  echo

  security_audit_section "1) SYSTEM IDENTITY / OS / BOOT"
  hostnamectl 2>/dev/null || true
  echo
  cat /etc/fedora-release 2>/dev/null || true
  echo
  uname -a
  echo
  echo "Boot mode: $(baseline_uefi_label)"

  security_audit_section "2) STORAGE / MOUNTS / ENCRYPTION"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,LABEL,MODEL,UUID 2>/dev/null || true
  echo
  df -hT
  echo
  findmnt 2>/dev/null || true
  echo
  echo "fstab:"
  cat /etc/fstab 2>/dev/null || true
  echo
  echo "LUKS devices:"
  lsblk -f 2>/dev/null | grep -i luks || true

  security_audit_section "3) USERS / GROUPS / SUDO"
  echo "Local users with login shell:"
  awk -F: '$7 !~ /(nologin|false)$/ { print $1 ":" $3 ":" $4 ":" $6 ":" $7 }' /etc/passwd
  echo
  echo "Members of wheel:"
  getent group wheel 2>/dev/null || true
  echo
  echo "Sudoers includes:"
  security_audit_run ls -lah /etc/sudoers /etc/sudoers.d 2>/dev/null || true

  security_audit_section "4) UPDATE / PACKAGE STATE"
  security_audit_run dnf check || true
  if (( QUICK == 0 )); then
    echo
    echo "Pending updates (first 120 lines):"
    security_audit_run dnf check-update 2>/dev/null | head -120 || true
  else
    echo
    echo "Pending updates: (skipped — --quick)"
  fi
  echo
  echo "Enabled repos:"
  dnf repolist --enabled 2>/dev/null || true

  security_audit_section "5) SELINUX / AUDIT"
  getenforce 2>/dev/null || true
  sestatus 2>/dev/null || true
  echo
  if (( QUICK == 0 )); then
    echo "Recent SELinux denials:"
    security_audit_run ausearch -m AVC,USER_AVC -ts recent 2>/dev/null | tail -80 || true
  else
    echo "Recent SELinux denials: (skipped — --quick)"
  fi

  security_audit_section "6) FIREWALL"
  security_audit_run firewall-cmd --state || true
  echo
  echo "Default zone:"
  security_audit_run firewall-cmd --get-default-zone || true
  echo
  echo "Active zones:"
  security_audit_run firewall-cmd --get-active-zones || true
  echo
  echo "Default zone rules:"
  security_audit_run firewall-cmd --list-all || true
  echo
  echo "Strict research zone (${strict_zone}):"
  security_audit_run firewall-cmd --zone="${strict_zone}" --list-all 2>/dev/null || true
  echo
  echo "FedoraWorkstation zone (if present):"
  security_audit_run firewall-cmd --zone=FedoraWorkstation --list-all 2>/dev/null || true

  security_audit_section "7) NETWORK / LISTENING SERVICES"
  ip -br addr 2>/dev/null || true
  echo
  nmcli device status 2>/dev/null || true
  echo
  nmcli radio all 2>/dev/null || true
  echo
  echo "Listening TCP/UDP sockets:"
  security_audit_run ss -tulpen || true
  echo
  echo "Public listeners (non-localhost):"
  security_audit_public_listeners || true
  echo
  echo "Established connections:"
  security_audit_run ss -tunap state established 2>/dev/null || true

  security_audit_section "8) SSH CONFIG"
  echo "sshd status:"
  systemctl status sshd --no-pager 2>/dev/null | head -40 || true
  echo
  echo "sshd effective config (key items):"
  security_audit_run sshd -T 2>/dev/null \
    | grep -iE '^(permitrootlogin|passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication|maxauthtries|x11forwarding|allowusers|clientalive|allowtcpforwarding|allowagentforwarding|permitopen|port|listenaddress|gssapiauthentication)' \
    | sort || true
  echo
  echo "sshd config snippets:"
  security_audit_run ls -lah /etc/ssh/sshd_config.d 2>/dev/null || true
  echo
  security_audit_run cat /etc/ssh/sshd_config.d/*.conf 2>/dev/null || true

  security_audit_section "9) DATABASE / MARIADB"
  systemctl status mariadb --no-pager 2>/dev/null | head -50 || true
  echo
  mariadb --version 2>/dev/null || true
  echo
  echo "MariaDB socket view:"
  security_audit_run ss -tulpen 2>/dev/null | grep -iE '3306|mariadb|mysql' || true
  echo
  echo "MariaDB config files:"
  security_audit_run find /etc -maxdepth 4 \( -iname '*maria*' -o -iname '*mysql*' \) 2>/dev/null | sort || true
  echo
  if [[ -f /etc/my.cnf.d/90-fedora-toolkit-bind-localhost.cnf ]]; then
    echo "Toolkit MariaDB drop-in:"
    security_audit_run cat /etc/my.cnf.d/90-fedora-toolkit-bind-localhost.cnf 2>/dev/null || true
  fi

  security_audit_section "10) ENABLED SERVICES"
  systemctl list-unit-files --type=service --state=enabled --no-pager 2>/dev/null || true

  security_audit_section "11) RUNNING SERVICES"
  systemctl --type=service --state=running --no-pager 2>/dev/null || true

  security_audit_section "12) TIMERS / SCHEDULED TASKS"
  systemctl list-timers --all --no-pager 2>/dev/null || true
  if (( QUICK == 0 )); then
    echo
    echo "User crontabs:"
    while IFS=: read -r u _ _ _ _ home shell; do
      hardening_has_login_shell "${shell}" || continue
      hardening_is_human_home "${home}" || continue
      echo "--- crontab for ${u} ---"
      security_audit_run crontab -l -u "${u}" 2>/dev/null || true
    done < <(getent passwd 2>/dev/null || true)
  else
    echo
    echo "User crontabs: (skipped — --quick)"
  fi
  echo
  echo "System cron dirs:"
  security_audit_run ls -lah /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly 2>/dev/null || true

  security_audit_section "13) WIRELESS / BLUETOOTH"
  echo "RFKill:"
  rfkill list 2>/dev/null || true
  echo
  echo "Bluetooth service:"
  systemctl status bluetooth --no-pager 2>/dev/null | head -40 || true
  echo
  echo "Wi-Fi devices:"
  nmcli device status 2>/dev/null | grep -iE 'wifi|wlan|wlo|p2p' || true

  security_audit_section "14) IMPORTANT LOGS / AUTH FAILURES"
  if (( QUICK == 0 )); then
    echo "Recent auth/ssh failures (last 120):"
    security_audit_run journalctl -b --no-pager 2>/dev/null \
      | grep -iE 'failed password|authentication failure|invalid user|sshd|sudo' | tail -120 || true
    echo
    echo "Warnings/errors this boot (last 160):"
    security_audit_run journalctl -b -p warning..alert --no-pager 2>/dev/null | tail -160 || true
  else
    echo "Journal excerpts: (skipped — --quick)"
  fi

  security_audit_section "15) HARDENING FILES / POLICY"
  echo "SSH snippets:"
  security_audit_run ls -lah /etc/ssh/sshd_config.d 2>/dev/null || true
  echo
  echo "Sysctl snippets:"
  security_audit_run ls -lah /etc/sysctl.d 2>/dev/null || true
  echo
  echo "Journald snippets:"
  security_audit_run ls -lah /etc/systemd/journald.conf.d 2>/dev/null || true
  echo
  echo "Resolved snippets:"
  security_audit_run ls -lah /etc/systemd/resolved.conf.d 2>/dev/null || true
  echo
  echo "Hardening baselines:"
  ls -lah "$(hardening_baseline_root)" 2>/dev/null | tail -20 || true
  echo
  for policy in /data/README_NEPTUNE_STORAGE_POLICY.txt /data/README_STORAGE_POLICY.txt; do
    if [[ -f "${policy}" ]]; then
      echo "Storage policy (${policy}):"
      cat "${policy}"
      echo
    fi
  done

  security_audit_section "16) SYSTEM HEALTH"
  free -h
  echo
  uptime
  if (( QUICK == 0 )); then
    echo
    echo "Top memory processes:"
    ps aux --sort=-%mem 2>/dev/null | head -20 || true
    echo
    echo "Top CPU processes:"
    ps aux --sort=-%cpu 2>/dev/null | head -20 || true
  else
    echo
    echo "Process top lists: (skipped — --quick)"
  fi

  security_audit_section "17) SUMMARY FLAGS"
  security_audit_print_summary_flags

  security_audit_print_findings_plain

  security_audit_section "19) RECOMMENDED ACTION PLAN"
  if [[ ${#SECURITY_AUDIT_ACTION_PLAN[@]} -eq 0 ]]; then
    echo "No remediation steps — host looks good for its profile."
    echo "Profile: $(hardening_research_profile_label | tr -d '\n')"
  else
    echo "Profile: $(hardening_research_profile_label | tr -d '\n')"
    local i=1 cmd
    for cmd in "${SECURITY_AUDIT_ACTION_PLAN[@]}"; do
      printf '%s) %s\n' "${i}" "${cmd}"
      i=$((i + 1))
    done
  fi

  security_audit_section "END OF AUDIT"
  echo "Report complete: ${out}"
}

_run_audit 2>&1 | tee "${out}"
security_audit_write_findings_file "${findings_out}"
security_audit_write_context_file "${context_out}"
host_context_save_snapshot "${stamp}" >/dev/null 2>&1 || true

echo
security_audit_print_findings_themed
echo
security_audit_print_action_plan

if (( COMPARE )); then
  if [[ -n "${prev_report}" && "${prev_report}" != "${out}" ]]; then
    echo
    security_audit_compare_with_previous "${prev_report}"
  fi
  if [[ -n "${prev_findings}" && "${prev_findings}" != "${findings_out}" ]]; then
    echo
    security_audit_compare_findings_with_previous "${prev_findings}"
  fi
  if [[ -n "${prev_context}" && "${prev_context}" != "${context_out}" ]]; then
    echo
    host_context_compare_snapshots "${prev_context}"
  fi
fi

audit_ec=0
(( $(security_audit_finding_count CRITICAL) > 0 )) && audit_ec=1

if (( audit_ec == 0 )); then
  theme_summary_box "Security audit complete" \
    "Host:      ${host}" \
    "Report:    ${out}" \
    "Findings:  ${findings_out}" \
    "Critical:  0"
else
  theme_summary_box "Security audit complete" \
    "Host:      ${host}" \
    "Report:    ${out}" \
    "Critical:  $(security_audit_finding_count CRITICAL) — see section 18" \
    "Next:      ./system/security_audit.sh --findings"
fi

exit "${audit_ec}"
