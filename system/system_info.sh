#!/usr/bin/env bash
# system_info.sh — Fedora environment documentation tool
# Version: 0.5.0 — delegates snapshot to lib/health.sh
#
# Run:
#   ./system/system_info.sh
#   ./system/system_info.sh --help

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/health.sh
source "${_SCRIPT_DIR}/../lib/health.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--help]

Print a readable host snapshot (OS, CPU, RAM, disk, network).
No sudo required. If run under sudo, shows invoking and effective user.

EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

health_print_system_info
