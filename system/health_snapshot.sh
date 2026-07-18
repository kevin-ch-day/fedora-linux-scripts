#!/usr/bin/env bash
# health_snapshot.sh — quick disk/memory snapshot + dashboard
# Version: 0.1.5
#
# Run:
#   ./system/health_snapshot.sh --show
#   ./system/health_snapshot.sh --refresh
#   ./system/health_snapshot.sh --export

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${_SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/health_snapshot.sh
source "${FEDORA_ROOT}/lib/health_snapshot.sh"

MODE="show"
QUIET=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Quick health snapshot and dashboard for disk, memory, swap, mounts, and cleanup targets.

Options:
  --help, -h     Show this help
  --show         Print dashboard (refresh if missing or older than 15m)
  --refresh      Refresh snapshot; print compact status unless --quiet
  --export       Export a fuller diagnostic report to runtime/health/history/
  --quiet        Suppress non-essential status lines

Files:
  runtime/health/latest.json
  runtime/health/latest.txt
  runtime/health/history/<stamp>.json
  runtime/health/history/<stamp>.txt
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --show) MODE="show"; shift ;;
    --refresh) MODE="refresh"; shift ;;
    --export) MODE="export"; shift ;;
    --quiet) QUIET=1; shift ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

case "${MODE}" in
  show)
    if [[ ! -f "$(health_snapshot_latest_txt)" ]] || health_snapshot_needs_refresh; then
      health_snapshot_refresh quick 1 "${FEDORA_VERBOSE:-0}" >/dev/null
    fi
    cat "$(health_snapshot_latest_txt)"
    ;;
  refresh)
    health_snapshot_refresh quick 1 "${FEDORA_VERBOSE:-0}" >/dev/null
    if (( QUIET == 0 )); then
      health_snapshot_print_refresh_summary
    fi
    ;;
  export)
    out="$(health_snapshot_export_full_report)"
    if (( QUIET == 0 )); then
      theme_init
      theme_set_lane audit
      theme_lane_banner "Full diagnostic report exported" audit ""
      theme_meta_line "REPORT / ${out}"
      theme_meta_line "LATEST / runtime/health/latest.txt"
      theme_status_info "OPEN / less ${out}"
    fi
    ;;
esac
