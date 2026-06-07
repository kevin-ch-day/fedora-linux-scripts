#!/usr/bin/env bash
# mobsf_start.sh — Start MobSF stack (no data wipe)
# Version: 0.1.0

set -euo pipefail

MOBSF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mobsf.sh
source "${MOBSF_DIR}/lib/mobsf.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      echo "Usage: $(basename "$0")"
      echo "Start MobSF stack (ordered: postgres → mobsf/djangoq → nginx)."
      echo "Run as user with podman, or: sudo -E $0"
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
done

mobsf_require_tools
mobsf_stack_up_ordered
mobsf_show_status
