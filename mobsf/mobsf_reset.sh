#!/usr/bin/env bash
# mobsf_reset.sh — Reset MobSF podman stack (nuke or keep data)
# Version: 0.3.0
#
# Run:
#   sudo -E ./mobsf/mobsf_reset.sh
#   sudo -E ./mobsf/mobsf_reset.sh --keep
#   sudo -E ./mobsf/mobsf_reset.sh --help

set -euo pipefail

MOBSF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${MOBSF_DIR}/.." && pwd)"
# shellcheck source=lib/mobsf.sh
source "${MOBSF_DIR}/lib/mobsf.sh"
# shellcheck source=../lib/logging.sh
source "${FEDORA_ROOT}/lib/logging.sh"

MODE="nuke"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep) MODE="keep"; shift ;;
    --help|-h)
      cat <<EOF
Usage: $(basename "$0") [--keep]

Stop, optionally wipe data, and rebuild the MobSF Podman stack.

  (default)  Remove ~/MobSF/mobsf_data and postgresql_data, then rebuild
  --keep     Keep data dirs; recreate containers only

Requires compose at ~/MobSF/compose/ (install with mobsf_install.sh first).

Run with: sudo -E $0
EOF
      exit 0
      ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

require_root "Run with: sudo -E ./mobsf/mobsf_reset.sh"
init_script_logging "${FEDORA_LOG_MOBSF}" "mobsf_reset.sh" "MobSF reset (${MODE})"

mobsf_stack_reset "${MODE}"
