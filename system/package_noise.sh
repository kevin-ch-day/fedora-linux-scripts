#!/usr/bin/env bash
# package_noise.sh — package/update background process check
# Version: 0.1.0
#
# Run:
#   ./system/package_noise.sh
#   ./system/package_noise.sh --stop-session   # stop helpers for this session (explicit)

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${_SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/readiness.sh
source "${FEDORA_ROOT}/lib/readiness.sh"
theme_init
theme_set_lane audit

STOP_SESSION=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Show running package/update background processes:
  dnf · PackageKit · dnfdragora · dnf5daemon · rpm · flatpak helpers

Options:
  --help, -h        Show this help
  --stop-session    Stop PackageKit/dnfdragora for this session (no package removal)

Also: ./system/system.sh package-noise
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --stop-session) STOP_SESSION=1; shift ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

theme_report_header "Package / update noise" \
  "Host: $(health_hostname)" \
  "Read-only unless --stop-session"

theme_section "Running processes"
if out="$(readiness_package_noise_list 2>/dev/null)"; then
  printf '%s\n' "${out}"
  warn "Background package activity detected"
else
  ok "No matching package/update background processes"
fi

if (( STOP_SESSION )); then
  theme_section "Session stop (explicit)"
  if [[ -t 0 ]]; then
    confirm "Stop background update helpers for this session?" || die "Cancelled"
  else
    die "--stop-session requires an interactive terminal for confirmation"
  fi
  readiness_package_noise_stop_session
  theme_section "After stop"
  if readiness_package_noise_list >/dev/null 2>&1; then
    warn "Some processes may still be running (dnf/rpm in another terminal)"
    readiness_package_noise_list | sed 's/^/  /'
  else
    ok "No matching background processes"
  fi
fi

echo
theme_result_ready "Package noise check complete"
