#!/usr/bin/env bash
# mobsf_status.sh — Show MobSF container status
# Version: 0.2.0
#
# Run:
#   ./mobsf/mobsf_status.sh
#   ./mobsf/mobsf_status.sh --help

set -euo pipefail

MOBSF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mobsf.sh
source "${MOBSF_DIR}/lib/mobsf.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      cat <<EOF
Usage: $(basename "$0") [--help]

Show MobSF Podman compose container status for $(real_user).
Compose dir, UI URL, and container table.

See also: ./mobsf/mobsf_doctor.sh  ./mobsf/mobsf.sh
EOF
      exit 0
      ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
done

mobsf_show_status
