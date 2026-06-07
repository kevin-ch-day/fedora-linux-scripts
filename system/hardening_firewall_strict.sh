#!/usr/bin/env bash
# hardening_firewall_strict.sh — custom strict firewalld zone (SSH only on wired)
# Version: 0.1.0
#
# Creates/uses zone: <hostname>-research (e.g. neptune-research on Neptune)
# Override: FEDORA_HARDENING_FIREWALL_ZONE=my-zone
#
# Run:
#   ./system/hardening_firewall_strict.sh --status
#   ./system/hardening_firewall_strict.sh --dry-run --yes
#   ./system/hardening_firewall_strict.sh --yes

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

usage() {
  local zone
  zone="$(hardening_firewall_strict_zone_name)"
  cat <<EOF
Usage: $(basename "$0") [options]

Strict firewall for wired research workstations:
  · Custom zone: ${zone} (ssh inbound only)
  · Removes FedoraWorkstation wide ports (1025-65535)
  · Binds active wired NetworkManager connections to strict zone
  · MariaDB stays local — not opened in firewall

Options:
  --status     Read-only firewall + listening ports
  --yes        Skip confirmation
  --dry-run    Preview only
  --force      Re-apply even if already strict
  --help,-h    Show this help

Logs: \$(hardening_firewall_log_dir)/pre_firewall_*.txt and post_firewall_*.txt

Also: ./system/hardening_round2.sh --yes --firewall-only
      ./system/system.sh firewall-strict

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
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

ZONE="$(hardening_firewall_strict_zone_name)"
LOG_DIR="$(hardening_firewall_log_dir)"

if (( STATUS_ONLY )); then
  theme_banner "Strict firewall status"
  hardening_print_host_banner_meta
  theme_meta_line "Strict zone: ${ZONE}"
  theme_rule '─'
  echo
  hardening_print_firewall_verify
  echo
  hardening_print_listening_services
  exit 0
fi

if (( YES == 0 )); then
  if [[ ! -t 0 ]]; then
    die "Non-interactive run requires --yes"
  fi
  theme_banner "Strict firewall — SSH only"
  hardening_print_host_banner_meta
  theme_meta_line "Strict zone: ${ZONE}"
  theme_rule '─'
  echo
  hardening_print_firewall_verify
  echo
  info "Will create/use zone ${ZONE} with ssh only (no MariaDB/HTTP in firewall)."
  info "Wired NM connections will be assigned to ${ZONE}."
  echo
  confirm "Harden firewall on $(health_hostname) to allow only SSH inbound?" || die "Aborted."
fi

stamp="$(date +%Y%m%d_%H%M%S)"
pre_log="${LOG_DIR}/pre_firewall_${stamp}.txt"
post_log="${LOG_DIR}/post_firewall_${stamp}.txt"

theme_banner "Strict firewall — SSH only"
hardening_print_host_banner_meta
theme_meta_line "Zone: ${ZONE}"
theme_meta_line "Logs: ${LOG_DIR}/"
if (( DRY_RUN )); then
  theme_meta_line "Mode: dry-run"
fi
theme_rule '─'
echo

if (( ! DRY_RUN )); then
  theme_section "Before"
  hardening_firewall_save_snapshot "pre" "${pre_log}"
  ok "Saved: ${pre_log}"
  echo
fi

if (( ! FORCE )) && ! hardening_round2_firewall_needs_hardening; then
  ok "Firewall: already strict on ${ZONE} (skipped; use --force to re-apply)"
else
  if (( DRY_RUN )); then
    hardening_firewall_apply_strict 1
  else
    hardening_firewall_apply_strict 0
  fi
fi
echo

theme_section "Verify"
hardening_print_firewall_verify
echo
hardening_print_listening_services
echo

if (( ! DRY_RUN )); then
  hardening_firewall_save_snapshot "post" "${post_log}"
  ok "Saved: ${post_log}"
fi

if (( DRY_RUN )); then
  theme_summary_box "Firewall dry-run complete" \
    "Zone:     ${ZONE}" \
    "Changes:  none applied" \
    "Run:      ./system/hardening_firewall_strict.sh --yes"
  exit 0
fi

theme_summary_box "Firewall hardening complete" \
  "Zone:      ${ZONE}" \
  "Expected:  services=ssh · ports=empty" \
  "Logs:      ${post_log}" \
  "Status:    ./system/hardening_firewall_strict.sh --status"
