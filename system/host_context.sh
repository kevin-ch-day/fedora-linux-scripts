#!/usr/bin/env bash
# host_context.sh — live host awareness snapshot (read-only)
# Version: 0.1.0
#
# Run:
#   ./system/host_context.sh
#   ./system/host_context.sh --summary
#   ./system/host_context.sh --save
#   ./system/host_context.sh --compare

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${_SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/host_context.sh
source "${FEDORA_ROOT}/lib/host_context.sh"
# shellcheck source=../lib/hardening.sh
source "${FEDORA_ROOT}/lib/hardening.sh"
theme_init

SAVE=0
COMPARE=0
SUMMARY=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Read-only host context — users, network, system posture.

Modes:
  (default)    key=value snapshot to stdout
  --summary    Human-readable summary + remediation notes
  --save       Write snapshot under logs/host_context/<host>/
  --compare    Diff live snapshot vs latest saved on this host

Also: ./run.sh --host-context
      ./system/system.sh host-context

Toolkit root: ${FEDORA_ROOT}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --summary) SUMMARY=1; shift ;;
    --save) SAVE=1; shift ;;
    --compare) COMPARE=1; shift ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

if (( SUMMARY )); then
  theme_banner "Host context"
  host_context_print_banner
  theme_rule '─'
  echo
  host_context_print_summary | sed '1d'
  echo
  host_context_remediation_notes
  exit 0
fi

if (( SAVE )); then
  path="$(host_context_save_snapshot)"
  theme_banner "Host context saved"
  theme_meta_line "Path: ${path}"
  host_context_snapshot | sed 's/^/  /'
  exit 0
fi

if (( COMPARE )); then
  prev="$(host_context_latest_snapshot_path 2>/dev/null || true)"
  theme_banner "Host context — compare"
  host_context_print_banner
  theme_rule '─'
  echo
  if [[ -z "${prev}" ]]; then
    info "No saved snapshot on this host — run ./system/host_context.sh --save first"
    exit 0
  fi
  host_context_compare_snapshots "${prev}"
  exit 0
fi

host_context_snapshot
