#!/usr/bin/env bash
# mobsf/lib/mobsf.sh — MobSF shared library loader
# Version: 0.2.0
#
# Source from MobSF scripts:
#   MOBSF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck source=lib/mobsf.sh
#   source "${MOBSF_DIR}/lib/mobsf.sh"
#
# Do not execute directly.

if [[ -n "${FEDORA_MOBSF_LIB_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_MOBSF_LIB_LOADED=1

_MOBSF_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
_FEDORA_ROOT="$(cd -- "${_MOBSF_LIB_DIR}/../.." && pwd)"

# shellcheck source=../../lib/common.sh
source "${_FEDORA_ROOT}/lib/common.sh"

# shellcheck source=config.sh
source "${_MOBSF_LIB_DIR}/config.sh"
# shellcheck source=paths.sh
source "${_MOBSF_LIB_DIR}/paths.sh"
# shellcheck source=podman.sh
source "${_MOBSF_LIB_DIR}/podman.sh"
# shellcheck source=compose.sh
source "${_MOBSF_LIB_DIR}/compose.sh"
# shellcheck source=stack.sh
source "${_MOBSF_LIB_DIR}/stack.sh"
# shellcheck source=doctor.sh
source "${_MOBSF_LIB_DIR}/doctor.sh"
# shellcheck source=systemd.sh
source "${_MOBSF_LIB_DIR}/systemd.sh"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
