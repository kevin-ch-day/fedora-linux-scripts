#!/usr/bin/env bash
# mobsf_stop.sh — Stop MobSF stack
# Version: 0.1.0

set -euo pipefail

MOBSF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mobsf.sh
source "${MOBSF_DIR}/lib/mobsf.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      echo "Usage: $(basename "$0")"
      echo "Stop MobSF podman-compose stack."
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
done

mobsf_require_tools
mobsf_stack_down
ok "MobSF stack stopped"
