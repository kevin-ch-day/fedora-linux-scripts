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
Usage: $(basename "$0") [--help] [--context]

Print a readable host snapshot (OS, CPU, RAM, disk, network).
Appends host context summary (users, network posture) unless --context only.
No sudo required. If run under sudo, shows invoking and effective user.

EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --context)
      # shellcheck source=../lib/host_context.sh
      source "${_SCRIPT_DIR}/../lib/host_context.sh"
      host_context_print_summary
      exit 0
      ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

health_print_system_info
echo
# shellcheck source=../lib/host_context.sh
source "${_SCRIPT_DIR}/../lib/host_context.sh"
host_context_print_summary
