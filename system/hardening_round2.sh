#!/usr/bin/env bash
# hardening_round2.sh — conservative firewall + service reduction
# Version: 0.1.0
#
# Strict research profile: public zone with SSH only, disable discovery/print/VM extras.
# Does not touch MariaDB or SSH password auth (Round 1 preserved).
#
# Run:
#   ./system/hardening_round2.sh --status
#   ./system/hardening_round2.sh --dry-run --yes
#   ./system/hardening_round2.sh --yes
#   ./system/hardening_round2.sh --yes --firewall-only
#   ./system/hardening_round2.sh --yes --include-review   # sssd, homed, VM agents

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
INCLUDE_REVIEW=0
FIREWALL_ONLY=0
SERVICES_ONLY=0
WIRED_ONLY=0
LISTENING_ONLY=0
BASE_ROOT=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Round 2 — conservative firewall + service reduction for research workstations:
  · Custom strict zone (<host>-research): ssh only, no wide ports
  · Disable safe-tier services: bluetooth, avahi, cups, ModemManager, …
  · MariaDB stays local — not exposed through firewall
  · SSH password auth unchanged (Round 1)

Options:
  --status            Show Round 2 status (read-only)
  --yes               Skip confirmation
  --dry-run           Preview only
  --force             Re-apply firewall rules even if already strict
  --firewall-only     Firewall changes only (no service disables)
  --services-only     Service disables only (no firewall changes)
  --wired-only        Also mask Bluetooth and disable Wi-Fi radio
  --listening-only    Listening hardening only (MariaDB, Avahi, CUPS, LLMNR, BT/Wi-Fi)
  --include-review    Also disable review-tier units (sssd, homed, VM guest agents)
  --base-dir PATH     Baseline log root (default: same as Round 1)
  --help, -h          Show this help

Recommended flow:
  ./system/hardening_services_audit.sh
  ./system/hardening_round2.sh --dry-run --yes
  ./system/hardening_round2.sh --yes

Also: ./system/system.sh hardening-round2
      System maintenance → [11] Hardening and security → Round 2 → [1]

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
    --include-review) INCLUDE_REVIEW=1; shift ;;
    --firewall-only) FIREWALL_ONLY=1; shift ;;
    --services-only) SERVICES_ONLY=1; shift ;;
    --wired-only) WIRED_ONLY=1; shift ;;
    --listening-only) LISTENING_ONLY=1; shift ;;
    --base-dir) BASE_ROOT="${2:?--base-dir requires a path}"; shift 2 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

if (( FIREWALL_ONLY && SERVICES_ONLY )); then
  die "Use only one of --firewall-only or --services-only"
fi

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

_hardening_save_baseline() {
  local session_dir="$1"
  local out="${session_dir}/round2_prechange.txt"
  if (( DRY_RUN )); then
    info "[dry-run] would save pre-change snapshot to ${out}"
    return 0
  fi
  mkdir -p "${session_dir}"
  {
    echo "===== METADATA ====="
    echo "Captured: $(date -Iseconds)"
    echo "Hostname: $(health_hostname)"
    echo "OS: $(hardening_os_label)"
    echo "Round: 2"
    echo
    echo "===== FIREWALL (before) ====="
    _hardening_run_root firewall-cmd --get-default-zone 2>/dev/null || true
    _hardening_run_root firewall-cmd --get-active-zones 2>/dev/null || true
    _hardening_run_root firewall-cmd --list-all 2>/dev/null || true
    echo
    echo "===== SERVICES (enabled) ====="
    systemctl list-unit-files --type=service --state=enabled 2>/dev/null || true
    echo
    echo "===== SOCKETS (enabled) ====="
    systemctl list-unit-files --type=socket --state=enabled 2>/dev/null || true
  } | tee "${out}"
  ok "Pre-change snapshot: ${out}"
}

_hardening_apply_firewall_strict() {
  if (( SERVICES_ONLY )); then
    info "Firewall step skipped (--services-only)"
    return 0
  fi
  if ! have firewall-cmd; then
    warn "firewalld not installed — skipping firewall step"
    return 0
  fi

  local zone pre_log stamp
  zone="$(hardening_firewall_strict_zone_name)"

  if (( ! FORCE )) && ! hardening_round2_firewall_needs_hardening; then
    ok "Firewall: already strict on ${zone} (skipped; use --force to re-apply)"
    return 0
  fi

  info "Hardening firewall → zone ${zone} (ssh only, wired NM binding)..."

  if (( DRY_RUN )); then
    hardening_firewall_apply_strict 1
    return 0
  fi

  stamp="$(date +%Y%m%d_%H%M%S)"
  pre_log="$(hardening_firewall_log_dir)/pre_firewall_${stamp}.txt"
  hardening_firewall_save_snapshot "round2-pre" "${pre_log}"

  hardening_firewall_apply_strict 0

  hardening_firewall_save_snapshot "round2-post" "$(hardening_firewall_log_dir)/post_firewall_${stamp}.txt"
}

_hardening_disable_unit() {
  local unit="$1"
  if [[ "${unit}" == "bluetooth" ]]; then
    hardening_disable_bluetooth "${DRY_RUN}"
    return 0
  fi
  if ! hardening_round2_service_needs_disable "${unit}"; then
    if hardening_unit_exists "${unit}" && hardening_unit_is_disabled "${unit}"; then
      ok "${unit}: already disabled (skipped)"
    fi
    return 0
  fi
  info "Disabling ${unit}..."
  if (( DRY_RUN )); then
    info "[dry-run] systemctl disable --now ${unit}"
    return 0
  fi
  _hardening_run_root systemctl disable --now "${unit}" 2>/dev/null \
    || _hardening_run_root systemctl disable "${unit}" 2>/dev/null \
    || warn "${unit}: could not disable"
  ok "${unit}: disabled"
}

_hardening_apply_services() {
  if (( FIREWALL_ONLY )); then
    info "Service step skipped (--firewall-only)"
    return 0
  fi
  local unit
  while IFS= read -r unit; do
    [[ -n "${unit}" ]] || continue
    _hardening_disable_unit "${unit}"
  done < <(hardening_round2_services_for_run "${INCLUDE_REVIEW}")
}

_hardening_verify() {
  hardening_print_firewall_verify
  echo
  hardening_print_listening_services
  echo
  theme_section "Services (safe tier)"
  local unit
  while IFS= read -r unit; do
    [[ -n "${unit}" ]] || continue
    hardening_unit_exists "${unit}" || continue
    printf '    %-24s %s\n' "${unit}" "$(systemctl is-enabled "${unit}" 2>/dev/null || echo n/a)"
  done < <(hardening_round2_services_for_run 0)
  echo
  info "MariaDB (unchanged): $(systemctl is-active mariadb 2>/dev/null || echo not installed)"
  info "sshd AllowUsers: $(hardening_sshd_effective_allow_users 2>/dev/null || echo unknown)"
}

if (( STATUS_ONLY )); then
  theme_banner "OS hardening — Round 2 status"
  hardening_print_host_banner_meta
  theme_rule '─'
  echo
  hardening_preflight_or_warn || true
  echo
  hardening_print_round1_status
  echo
  hardening_print_round2_status
  echo
  hardening_print_listening_status
  echo
  hardening_print_listening_audit
  exit 0
fi

if [[ "${EUID}" -ne 0 ]]; then
  if (( YES == 0 )); then
    if [[ ! -t 0 ]]; then
      die "Non-interactive run requires --yes"
    fi
    theme_banner "OS hardening — Round 2"
    hardening_print_host_banner_meta
    theme_rule '─'
    echo
    if ! hardening_round1_complete; then
      warn "Round 1 is incomplete on this host — finish Round 1 first if possible"
    else
      ok "Round 1: complete"
    fi
    echo
    hardening_print_round2_plan strict "${INCLUDE_REVIEW}" "${FIREWALL_ONLY}" "${SERVICES_ONLY}"
    echo
    info "Strict research profile: only SSH exposed; MariaDB stays local."
    info "Review-tier units (sssd, homed, VM tools) skipped unless --include-review."
    echo
    confirm "Run OS hardening Round 2 on $(health_hostname)?" || die "Aborted."
  fi
fi

stamp="$(date +%Y%m%d_%H%M%S)"
session_dir="$(hardening_baseline_session_dir "$(hardening_baseline_root "${BASE_ROOT}")" "${stamp}")/round2"

theme_banner "OS hardening — Round 2"
hardening_print_host_banner_meta
theme_meta_line "Snapshot: ${session_dir}"
if (( DRY_RUN )); then
  theme_meta_line "Mode: dry-run"
elif (( INCLUDE_REVIEW )); then
  theme_meta_line "Mode: strict + review-tier service disables"
elif (( FIREWALL_ONLY )); then
  theme_meta_line "Mode: firewall only"
elif (( SERVICES_ONLY )); then
  theme_meta_line "Mode: services only"
else
  theme_meta_line "Mode: strict (firewall + safe services)"
fi
theme_rule '─'
echo

hardening_preflight_or_warn || true
echo

if (( LISTENING_ONLY )); then
  info "Listening-only mode — firewall unchanged"
  echo
  hardening_apply_listening_hardening "${DRY_RUN}" 0
  echo
  hardening_print_listening_audit
  echo
  if (( DRY_RUN )); then
    theme_summary_box "Listening dry-run complete" \
      "Run:  ./system/hardening_listening.sh --yes"
    exit 0
  fi
  theme_summary_box "Listening hardening complete" \
    "Host:   $(health_hostname)" \
    "Verify: ./system/hardening_listening.sh --status"
  exit 0
fi

_hardening_save_baseline "${session_dir}"
echo
_hardening_apply_firewall_strict
echo
_hardening_apply_services
echo
if (( WIRED_ONLY )); then
  theme_section "Wired-only (Bluetooth + Wi-Fi)"
  if ! hardening_wired_ethernet_connected; then
    warn "No connected Ethernet detected — verify wired path before relying on network"
  fi
  hardening_apply_wired_only "${DRY_RUN}"
  echo
fi
_hardening_verify
echo

if (( DRY_RUN )); then
  theme_summary_box "Round 2 dry-run complete" \
    "Host:     $(health_hostname)" \
    "Changes:  none applied" \
    "Run:      ./system/hardening_round2.sh --yes"
  exit 0
fi

theme_summary_box "Round 2 complete" \
  "Host:      $(health_hostname)" \
  "Profile:   strict (ssh only on firewall)" \
  "Status:    ./system/hardening_round2.sh --status" \
  "Note:      MariaDB local only · password SSH unchanged"
