#!/usr/bin/env bash
# hardening_round1.sh — safe OS hardening baseline (Round 1)
# Version: 0.3.0
#
# Auto-detects hostname, OS, profile, and SSH AllowUsers.
# Idempotent: skips steps already applied (use --force to re-apply).
#
# Run:
#   ./system/hardening_round1.sh --status
#   ./system/hardening_round1.sh --dry-run
#   ./system/hardening_round1.sh --yes
#   ./system/hardening_round1.sh --yes --allow-users wheel

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${_SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/hardening.sh
source "${FEDORA_ROOT}/lib/hardening.sh"
# shellcheck source=../lib/theme.sh
source "${FEDORA_ROOT}/lib/theme.sh"
theme_init

YES=0
DRY_RUN=0
FORCE=0
STATUS_ONLY=0
ALLOW_USERS_MODE=""
BASE_ROOT=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Round 1 — safe OS hardening (Fedora research workstations):
  · baseline snapshot under logs/hardening/<host>/<stamp>/
  · SELinux enforcing
  · SSH baseline (password login kept; AllowUsers auto-detected)
  · network sysctl hardening
  · persistent journald with size cap
  · firewalld + fstrim.timer + ssh service

Host, OS, profile, and users are detected automatically.

Options:
  --status           Show Round 1 status on this host (read-only)
  --yes              Skip confirmation prompt
  --dry-run          Show planned actions (no system changes)
  --force            Re-apply even if a step is already configured
  --allow-users U    auto | wheel | login | user1 user2 (default: auto)
  --base-dir PATH    Baseline root (or FEDORA_HARDENING_LOG_ROOT env)
  --help, -h         Show this help

AllowUsers modes:
  auto    wheel admins if any, else /home/* login users (+ merge existing sshd)
  wheel   wheel group only (falls back to login if wheel empty)
  login   all /home/* interactive accounts

Also: ./system/system.sh hardening-round1
      System maintenance → [11] Hardening and security → Round 1 → [1]

Round 2 prep: ./system/hardening_services_audit.sh

Toolkit root: ${FEDORA_ROOT}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --status) STATUS_ONLY=1; shift ;;
    --yes) YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --force) FORCE=1; shift ;;
    --allow-users) ALLOW_USERS_MODE="${2:?--allow-users requires a value}"; shift 2 ;;
    --base-dir) BASE_ROOT="${2:?--base-dir requires a path}"; shift 2 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

ALLOW_USERS="$(hardening_resolve_allow_users "${ALLOW_USERS_MODE}")"

SSHD_DROPIN="$(hardening_sshd_dropin)"
SYSCTL_DROPIN="$(hardening_sysctl_dropin)"
JOURNALD_DROPIN="$(hardening_journald_dropin)"

_hardening_run_root() {
  if (( DRY_RUN )); then
    info "[dry-run] would run: $*"
    return 0
  fi
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

_hardening_write_root() {
  local dest="$1"
  shift
  if (( DRY_RUN )); then
    info "[dry-run] would write: ${dest}"
    printf '%s\n' "$@" | sed 's/^/    /'
    return 0
  fi
  _hardening_run_root mkdir -p "$(dirname "${dest}")"
  _hardening_run_root tee "${dest}" >/dev/null <<< "$*"
}

_hardening_should_apply() {
  local step="$1"
  (( FORCE )) && return 0
  [[ "$(hardening_step_status "${step}")" != ok ]]
}

_hardening_save_baseline() {
  local session_dir="$1"
  local out
  out="$(hardening_baseline_report_path "${session_dir}")"
  if (( DRY_RUN )); then
    info "[dry-run] would save baseline to ${out}"
    return 0
  fi
  mkdir -p "${session_dir}"
  {
    echo "===== METADATA ====="
    echo "Captured: $(date -Iseconds)"
    echo "Hostname: $(health_hostname)"
    echo "OS: $(hardening_os_label)"
    echo "Profile: $(hardening_profile_label)"
    echo "Invoker: $(hardening_invoker_label)"
    echo "AllowUsers mode: $(hardening_allow_users_mode_label "${ALLOW_USERS_MODE:-auto}" | tr -d '\n')"
    echo "AllowUsers resolved: ${ALLOW_USERS}"
    echo "Toolkit: ${FEDORA_ROOT}"
    echo
    echo "===== HOST ====="
    hostnamectl 2>/dev/null || true
    echo
    echo "===== OS ====="
    cat /etc/os-release 2>/dev/null || true
    cat /etc/fedora-release 2>/dev/null || true
    uname -a
    echo
    echo "===== STORAGE ====="
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,LABEL,MODEL,UUID 2>/dev/null || true
    df -hT
    echo
    echo "===== SERVICES (enabled) ====="
    systemctl list-unit-files --type=service --state=enabled 2>/dev/null || true
    echo
    echo "===== SERVICES (running) ====="
    systemctl --type=service --state=running 2>/dev/null || true
    echo
    echo "===== FIREWALL ====="
    _hardening_run_root firewall-cmd --get-active-zones 2>/dev/null || true
    _hardening_run_root firewall-cmd --list-all 2>/dev/null || true
    echo
    echo "===== SELINUX ====="
    getenforce 2>/dev/null || true
    sestatus 2>/dev/null || true
    echo
    echo "===== SSHD EFFECTIVE CONFIG ====="
    _hardening_run_root sshd -T 2>/dev/null | sort || true
  } | tee "${out}"
  ok "Baseline saved: ${out}"
}

_hardening_apply_selinux() {
  if ! _hardening_should_apply selinux; then
    ok "SELinux: already enforcing (skipped)"
    return 0
  fi
  info "Setting SELinux enforcing..."
  if (( DRY_RUN )); then
    info "[dry-run] setenforce 1; SELINUX=enforcing in /etc/selinux/config"
    return 0
  fi
  _hardening_run_root setenforce 1 2>/dev/null || true
  if [[ -f /etc/selinux/config ]]; then
    if grep -q '^SELINUX=' /etc/selinux/config; then
      _hardening_run_root sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
    else
      echo 'SELINUX=enforcing' | _hardening_run_root tee -a /etc/selinux/config >/dev/null
    fi
  fi
  ok "SELinux: $(getenforce 2>/dev/null || echo unknown)"
}

_hardening_apply_ssh() {
  if ! _hardening_should_apply ssh; then
    ok "SSH Round 1 drop-in: already present (skipped; use --force to overwrite)"
    return 0
  fi
  info "Hardening SSH (password login kept; AllowUsers=${ALLOW_USERS})..."
  local conf
  conf="$(cat <<EOF
${HARDENING_DROPIN_HEADER}
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication yes
KbdInteractiveAuthentication yes
MaxAuthTries 4
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowUsers ${ALLOW_USERS}
EOF
)"
  _hardening_write_root "${SSHD_DROPIN}" "${conf}"
  if (( DRY_RUN )); then
    info "[dry-run] sshd -t && systemctl reload sshd"
    return 0
  fi
  _hardening_run_root sshd -t
  if systemctl list-unit-files sshd.service >/dev/null 2>&1; then
    _hardening_run_root systemctl enable --now sshd 2>/dev/null \
      || _hardening_run_root systemctl enable sshd 2>/dev/null || true
    _hardening_run_root systemctl reload sshd
  else
    warn "sshd unit not installed — drop-in written but service not reloaded"
  fi
  ok "SSH drop-in: ${SSHD_DROPIN}"
}

_hardening_apply_sysctl() {
  if ! _hardening_should_apply sysctl; then
    ok "Network sysctl: already hardened (skipped)"
    return 0
  fi
  info "Applying network sysctl hardening..."
  local conf
  conf="$(cat <<'EOF'
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
EOF
)"
  _hardening_write_root "${SYSCTL_DROPIN}" "${conf}"
  if (( DRY_RUN )); then
    info "[dry-run] sysctl --system"
    return 0
  fi
  _hardening_run_root sysctl --system >/dev/null
  ok "Sysctl drop-in: ${SYSCTL_DROPIN}"
}

_hardening_apply_journald() {
  if ! _hardening_should_apply journald; then
    ok "Journald: already persistent (skipped)"
    return 0
  fi
  info "Making system journal persistent with size cap..."
  local conf
  conf="$(cat <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=1G
RuntimeMaxUse=256M
EOF
)"
  _hardening_write_root "${JOURNALD_DROPIN}" "${conf}"
  if (( DRY_RUN )); then
    info "[dry-run] systemctl restart systemd-journald"
    return 0
  fi
  _hardening_run_root systemctl restart systemd-journald
  ok "Journald drop-in: ${JOURNALD_DROPIN}"
}

_hardening_apply_firewall() {
  if ! _hardening_should_apply firewall; then
    ok "Firewall + fstrim: already configured (skipped)"
    return 0
  fi
  info "Confirming firewalld, fstrim.timer, and ssh through firewall..."
  if (( DRY_RUN )); then
    info "[dry-run] enable firewalld + fstrim.timer; firewall-cmd --add-service=ssh"
    return 0
  fi
  if have firewall-cmd; then
    _hardening_run_root systemctl enable --now firewalld
    _hardening_run_root firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1 || true
    _hardening_run_root firewall-cmd --reload
  else
    warn "firewalld not installed — skipping firewall step"
  fi
  _hardening_run_root systemctl enable --now fstrim.timer 2>/dev/null || true
  ok "firewalld + fstrim.timer configured; ssh allowed when firewalld present"
}

_hardening_verify() {
  theme_section "Round 1 verify"
  echo
  printf '  Host:           %s\n' "$(health_hostname)"
  printf '  OS:             %s\n' "$(hardening_os_label | tr -d '\n')"
  printf '  Profile:        %s\n' "$(hardening_profile_label | tr -d '\n')"
  printf '  User:           %s\n' "$(real_user)"
  printf '  SELinux:        %s\n' "$(getenforce 2>/dev/null || echo n/a)"
  local sshd_act sshd_en
  sshd_act="$(systemctl is-active sshd 2>/dev/null || true)"
  sshd_en="$(systemctl is-enabled sshd 2>/dev/null || true)"
  [[ -n "${sshd_act}" ]] || sshd_act="unknown"
  [[ -n "${sshd_en}" ]] || sshd_en="unknown"
  printf '  sshd:           %s (enabled: %s)\n' "${sshd_act}" "${sshd_en}"
  printf '  firewalld:      %s\n' "$(systemctl is-active firewalld 2>/dev/null || echo inactive)"
  printf '  fstrim.timer:   %s\n' "$(systemctl is-enabled fstrim.timer 2>/dev/null || echo unknown)"
  if findmnt -n /data >/dev/null 2>&1; then
    printf '  /data mount:    %s\n' "$(findmnt -no FSTYPE,OPTIONS /data 2>/dev/null || echo mounted)"
    df -hT /data 2>/dev/null | tail -n 1 | awk '{printf "  /data space:    %s used of %s (%s)\n", $4, $2, $6}'
  fi
  echo
  info "SSH effective settings:"
  if (( DRY_RUN )); then
    echo "  (skipped in dry-run)"
  else
    _hardening_run_root sshd -T 2>/dev/null \
      | grep -iE '^(permitrootlogin|passwordauthentication|pubkeyauthentication|maxauthtries|x11forwarding|allowusers|clientaliveinterval|clientalivecountmax)' \
      | sed 's/^/    /' || true
  fi
  echo
  if (( DRY_RUN )); then
    info "Firewall: (skipped in dry-run)"
  elif have firewall-cmd; then
    info "Firewall:"
    _hardening_run_root firewall-cmd --list-all 2>/dev/null | sed 's/^/    /' || true
  fi
}

if (( STATUS_ONLY )); then
  theme_banner "OS hardening — Round 1 status"
  hardening_print_host_banner_meta
  theme_rule '─'
  echo
  hardening_preflight_or_warn || true
  echo
  hardening_print_round1_status
  theme_meta_line "AllowUsers (auto now): $(hardening_resolve_allow_users "${ALLOW_USERS_MODE}")"
  exit 0
fi

# ---------- main ----------
if [[ "${EUID}" -ne 0 ]]; then
  if (( YES == 0 )); then
    if [[ ! -t 0 ]]; then
      die "Non-interactive run requires --yes (try: ./system/hardening_round1.sh --yes)"
    fi
    theme_banner "OS hardening — Round 1"
    hardening_print_host_banner_meta
    theme_rule '─'
    echo
    hardening_preflight_or_warn || true
    hardening_print_round1_plan "${ALLOW_USERS_MODE}"
    echo
    info "Password SSH login stays enabled (no lockout)."
    info "Does not disable services — run hardening_services_audit.sh before Round 2."
    echo
    confirm "Run OS hardening Round 1 on $(health_hostname)?" || die "Aborted."
  fi
fi

stamp="$(date +%Y%m%d_%H%M%S)"
session_dir="$(hardening_baseline_session_dir "$(hardening_baseline_root "${BASE_ROOT}")" "${stamp}")"
baseline_out="$(hardening_baseline_report_path "${session_dir}")"

theme_banner "OS hardening — Round 1"
hardening_print_host_banner_meta
theme_meta_line "Baseline: ${session_dir}"
theme_meta_line "AllowUsers: ${ALLOW_USERS} ($(hardening_allow_users_mode_label "${ALLOW_USERS_MODE:-auto}" | tr -d '\n'))"
if (( DRY_RUN )); then
  theme_meta_line "Mode: dry-run (no changes)"
elif (( FORCE )); then
  theme_meta_line "Mode: force (re-apply all steps)"
fi
theme_rule '─'
echo

hardening_preflight_or_warn || true
echo
_hardening_save_baseline "${session_dir}"
echo
_hardening_apply_selinux
_hardening_apply_ssh
_hardening_apply_sysctl
_hardening_apply_journald
_hardening_apply_firewall
echo
_hardening_verify
echo

if (( DRY_RUN )); then
  theme_summary_box "Round 1 dry-run complete" \
    "Host:     $(health_hostname)" \
    "Changes:  none applied" \
    "Run:      ./system/hardening_round1.sh --yes"
  exit 0
fi

if hardening_round1_complete; then
  result="complete"
else
  result="partial (re-run or use --force)"
fi

theme_summary_box "Round 1 ${result}" \
  "Host:      $(health_hostname)" \
  "Baseline:  ${baseline_out}" \
  "Status:    ./system/hardening_round1.sh --status" \
  "Next:      ./system/hardening_services_audit.sh"
