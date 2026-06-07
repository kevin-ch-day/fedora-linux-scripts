#!/usr/bin/env bash
# hardening_listening.sh — reduce listening services (MariaDB, Avahi, LLMNR, …)
# Version: 0.1.0
#
# Run after firewall strict zone is in place. Does not change firewall rules.
#
# Run:
#   ./system/hardening_listening.sh --status
#   ./system/hardening_listening.sh --dry-run --yes
#   ./system/hardening_listening.sh --yes
#   ./system/hardening_listening.sh --yes --skip-wifi   # BT only, keep wifi radio check

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
SKIP_WIFI=0
MARIADB_ONLY=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Reduce network listening surface (after firewall strict zone):
  1. MariaDB → bind 127.0.0.1 only
  2. Disable Avahi (mDNS)
  3. Disable CUPS (printing)
  4. Wired only: mask Bluetooth + disable Wi-Fi radio
  5. systemd-resolved: LLMNR=no MulticastDNS=no

Does not modify firewalld zones. SSH password auth unchanged.

Options:
  --status         Read-only audit (ss -tulpen + checks)
  --yes            Skip confirmation
  --dry-run        Preview only
  --mariadb-only   Only bind MariaDB to localhost
  --skip-wifi      Disable Bluetooth only (do not turn off Wi-Fi radio)
  --help,-h        Show this help

Also: ./system/system.sh listening-harden
      System menu → [8] OS hardening → [8]

Toolkit root: ${FEDORA_ROOT}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --status) STATUS_ONLY=1; shift ;;
    --yes) YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --mariadb-only) MARIADB_ONLY=1; shift ;;
    --skip-wifi) SKIP_WIFI=1; shift ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

if (( STATUS_ONLY )); then
  theme_banner "Listening hardening status"
  hardening_print_host_banner_meta
  theme_rule '─'
  echo
  hardening_print_firewall_verify
  echo
  hardening_print_listening_status
  echo
  hardening_print_listening_audit
  exit 0
fi

if (( YES == 0 )); then
  if [[ ! -t 0 ]]; then
    die "Non-interactive run requires --yes"
  fi
  theme_banner "Listening hardening"
  hardening_print_host_banner_meta
  theme_rule '─'
  echo
  hardening_print_listening_audit
  echo
  info "Firewall zones are not changed by this script."
  if (( MARIADB_ONLY )); then
    info "Mode: MariaDB localhost bind only."
  else
    info "Order: MariaDB → Avahi → CUPS → BT/Wi-Fi → LLMNR → verify"
  fi
  echo
  confirm "Apply listening hardening on $(health_hostname)?" || die "Aborted."
fi

theme_banner "Listening hardening"
hardening_print_host_banner_meta
if (( DRY_RUN )); then
  theme_meta_line "Mode: dry-run"
elif (( MARIADB_ONLY )); then
  theme_meta_line "Mode: mariadb-only"
fi
theme_rule '─'
echo

if (( MARIADB_ONLY )); then
  hardening_bind_mariadb_localhost "${DRY_RUN}"
else
  hardening_apply_listening_hardening "${DRY_RUN}" "${SKIP_WIFI}"
fi
echo
hardening_print_listening_audit
echo

if (( DRY_RUN )); then
  theme_summary_box "Listening dry-run complete" \
    "Changes:  none applied" \
    "Run:      ./system/hardening_listening.sh --yes"
  exit 0
fi

theme_summary_box "Listening hardening complete" \
  "Host:     $(health_hostname)" \
  "Verify:   ./system/hardening_listening.sh --status" \
  "Check:    ss -tulpen (mariadb 127.0.0.1 · ssh :22 only public)"
