#!/usr/bin/env bash
# btrfs_health.sh — read-only Btrfs health (optional scrub with explicit flag)
# Version: 0.1.0
#
# Run:
#   ./system/btrfs_health.sh
#   ./system/btrfs_health.sh --scrub   # starts scrub on / — requires confirmation

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${_SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/readiness.sh
source "${FEDORA_ROOT}/lib/readiness.sh"
theme_init
theme_set_lane audit

DO_SCRUB=0
MOUNT="/"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Read-only Btrfs health for the root filesystem.
Never runs btrfs check --repair.

Options:
  --help, -h   Show this help
  --scrub      Start a scrub on / (interactive confirm; sudo required)

Also: ./system/system.sh btrfs-health
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --scrub) DO_SCRUB=1; shift ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

ISSUES=0

theme_report_header "Btrfs health" \
  "Host: $(health_hostname) · Mount: ${MOUNT}" \
  "Read-only by default · no btrfs check --repair"

if ! readiness_root_is_btrfs; then
  warn "Root filesystem is not btrfs"
  exit 1
fi

theme_section "Device stats"
stats="$(readiness_btrfs_device_stats "${MOUNT}" 2>/dev/null || true)"
if [[ -n "${stats}" ]]; then
  printf '%s\n' "${stats}"
  if grep -qE 'corruption_errs[[:space:]]+[1-9]' <<< "${stats}"; then
    warn "Non-zero corruption_errs detected — investigate replaceable caches (Cursor/VS Code/Chromium/SDK)"
    ISSUES=$((ISSUES + 1))
  else
    ok "corruption_errs: 0"
  fi
else
  warn "Could not read btrfs device stats"
  ISSUES=$((ISSUES + 1))
fi

theme_section "Scrub status"
scrub="$(readiness_btrfs_scrub_status "${MOUNT}" 2>/dev/null || true)"
if [[ -n "${scrub}" ]]; then
  if [[ "${scrub}" == *"requires sudo"* ]]; then
    theme_note "${scrub}"
    theme_note "Run: sudo ./system/system.sh btrfs-health"
  else
    printf '%s\n' "${scrub}"
    if grep -qi 'no errors found' <<< "${scrub}"; then
      ok "Latest scrub: no errors found"
    elif grep -qi 'errors found' <<< "${scrub}"; then
      warn "Scrub reported errors — review output above"
      ISSUES=$((ISSUES + 1))
    fi
  fi
else
  theme_note "No scrub status returned"
fi

if (( DO_SCRUB )); then
  theme_section "Scrub action"
  warn "Starting a scrub reads every block on the filesystem — can take hours on large drives."
  if ! confirm "Start btrfs scrub on ${MOUNT} now?"; then
    info "Scrub cancelled"
  elif [[ "${EUID}" -ne 0 ]]; then
    if confirm "Scrub requires sudo — continue?"; then
      sudo btrfs scrub start "${MOUNT}" && ok "Scrub started" || warn "Scrub start failed"
    fi
  else
    btrfs scrub start "${MOUNT}" && ok "Scrub started" || warn "Scrub start failed"
  fi
  theme_note "Monitor: btrfs scrub status ${MOUNT}"
fi

echo
if (( ISSUES > 0 )); then
  theme_summary_box "Btrfs summary" "Result: REVIEW" "Issues: ${ISSUES}"
  exit 1
fi
theme_summary_box "Btrfs summary" "Result: OK" "corruption_errs: 0 (if btrfs available)"
exit 0
