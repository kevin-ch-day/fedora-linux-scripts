#!/usr/bin/env bash
# mobsf_logs.sh — Tail MobSF stack service logs
# Version: 0.1.0
#
# Run:
#   ./mobsf/mobsf_logs.sh mobsf
#   ./mobsf/mobsf_logs.sh djangoq --tail 100
#   ./mobsf/mobsf_logs.sh nginx --follow

set -euo pipefail

MOBSF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mobsf.sh
source "${MOBSF_DIR}/lib/mobsf.sh"

SERVICE="mobsf"
TAIL=100
FOLLOW=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tail|-n) TAIL="${2:-100}"; shift 2 ;;
    --follow|-f) FOLLOW=1; shift ;;
    --help|-h)
      echo "Usage: $(basename "$0") [mobsf|djangoq|postgres|nginx] [--tail N] [--follow]"
      exit 0
      ;;
    mobsf|djangoq|postgres|nginx) SERVICE="$1"; shift ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

mobsf_require_tools
mobsf_compose_cd || die "Compose dir not found — run mobsf_install.sh"

if (( FOLLOW )); then
  exec mobsf_pc logs -f "${SERVICE}"
else
  mobsf_pc logs --tail="${TAIL}" "${SERVICE}"
fi
