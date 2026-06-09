#!/usr/bin/env bash
# daily_driver_check.sh — read-only daily driver / workstation readiness report
# Version: 0.1.0
#
# Run:
#   ./system/daily_driver_check.sh
#   ./system/system.sh daily-driver
#   ./run.sh --daily-driver-check

set -uo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${_SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/readiness.sh
source "${FEDORA_ROOT}/lib/readiness.sh"
theme_init

usage() {
  cat <<EOF
Usage: $(basename "$0") [--help]

Read-only daily driver check for a Fedora research workstation.
Reports boot, btrfs, LUKS, VirtualBox, package noise, and key mounts.

Also: ./run.sh --daily-driver-check
      ./system/system.sh daily-driver

Toolkit root: ${FEDORA_ROOT}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

readiness_print_daily_driver
