#!/usr/bin/env bash
# mobsf_cleanup.sh — Remove stopped MobSF compose containers (orphan cleanup)
# Version: 0.1.0
#
# Run:
#   ./mobsf/mobsf_cleanup.sh
#   ./mobsf/mobsf_cleanup.sh --help

set -euo pipefail

MOBSF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mobsf.sh
source "${MOBSF_DIR}/lib/mobsf.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      cat <<EOF
Usage: $(basename "$0")

Removes stopped MobSF Podman containers (compose service labels).
Does not delete ~/MobSF/mobsf_data or postgresql_data.

Use before mobsf_install.sh if old containers block a fresh deploy.
EOF
      exit 0
      ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

mobsf_require_tools
mobsf_cleanup_orphans
echo "[NEXT] sudo -E ./mobsf/mobsf_install.sh  OR  ./mobsf/mobsf_start.sh"
