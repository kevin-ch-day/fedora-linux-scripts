#!/usr/bin/env bash
# hardening_wired_only.sh — disable Bluetooth and Wi-Fi (wired Ethernet only)
# Version: 0.1.0
#
# For research hosts on wired Ethernet. Masks bluetooth.service and turns Wi-Fi off.
# Does not touch NetworkManager wired connections.
#
# Run:
#   ./system/hardening_wired_only.sh --status
#   ./system/hardening_wired_only.sh --dry-run --yes
#   ./system/hardening_wired_only.sh --yes

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
STATUS_ONLY=0
SKIP_ETH_CHECK=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Disable Bluetooth and Wi-Fi for wired-only research workstations:
  · systemctl disable --now + mask bluetooth.service
  · nmcli radio wifi off
  · rfkill block wifi (when available)

Ethernet (NetworkManager) is left unchanged.

Options:
  --status           Read-only status
  --yes              Skip confirmation
  --dry-run          Preview only
  --skip-eth-check   Apply even if no wired link detected (not recommended)
  --help, -h         Show this help

Also: ./system/system.sh wired-only
      System maintenance → [11] Hardening and security → Round 2 → [4]

Expected after apply:
  Bluetooth: masked / inactive
  Wi-Fi:     disabled (nmcli) + rfkill blocked

Toolkit root: ${FEDORA_ROOT}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --status) STATUS_ONLY=1; shift ;;
    --yes) YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --skip-eth-check) SKIP_ETH_CHECK=1; shift ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

if (( STATUS_ONLY )); then
  theme_banner "Wired-only status"
  hardening_print_host_banner_meta
  theme_rule '─'
  echo
  hardening_print_wired_only_status
  if hardening_wired_only_complete; then
    ok "Wired-only profile: active"
  else
    info "Wired-only profile: not fully applied"
  fi
  have rfkill && rfkill list 2>/dev/null | sed 's/^/  /' || true
  exit 0
fi

if (( YES == 0 )); then
  if [[ ! -t 0 ]]; then
    die "Non-interactive run requires --yes"
  fi
  theme_banner "Wired-only — disable Bluetooth & Wi-Fi"
  hardening_print_host_banner_meta
  theme_rule '─'
  echo
  hardening_print_wired_only_status
  echo
  if (( SKIP_ETH_CHECK == 0 )) && ! hardening_wired_ethernet_connected; then
    warn "No connected Ethernet link detected — confirm wired networking works before continuing"
  fi
  confirm "Disable Bluetooth and Wi-Fi on $(health_hostname)?" || die "Aborted."
fi

theme_banner "Wired-only — disable Bluetooth & Wi-Fi"
hardening_print_host_banner_meta
if (( DRY_RUN )); then
  theme_meta_line "Mode: dry-run"
fi
theme_rule '─'
echo

if (( SKIP_ETH_CHECK == 0 )) && ! hardening_wired_ethernet_connected; then
  die "No connected Ethernet link — use --skip-eth-check to override (unsafe)"
fi

theme_section "Before"
hardening_print_nmcli_radios || true
hardening_print_nmcli_devices || true
theme_meta_line "Bluetooth: $(hardening_bluetooth_unit_state | tr '\n' ' ')"
echo

theme_section "Apply"
hardening_apply_wired_only "${DRY_RUN}"
echo

theme_section "Verify"
hardening_print_wired_only_status
if have rfkill; then
  echo
  theme_meta_line "rfkill:"
  rfkill list 2>/dev/null | sed 's/^/  /' || true
fi
echo

if (( DRY_RUN )); then
  theme_summary_box "Wired-only dry-run complete" \
    "Changes:  none applied" \
    "Run:      ./system/hardening_wired_only.sh --yes"
  exit 0
fi

theme_summary_box "Wired-only complete" \
  "Host:       $(health_hostname)" \
  "Bluetooth:  masked + inactive expected" \
  "Wi-Fi:      radio off" \
  "Ethernet:   unchanged (NetworkManager)"
