#!/usr/bin/env bash
# lib/mobsf.sh — backward-compatible shim → mobsf/lib/mobsf.sh
# Version: 0.2.0
#
# Prefer sourcing mobsf/lib/mobsf.sh from MobSF scripts. Entry: ./mobsf.sh

if [[ -n "${FEDORA_MOBSF_LIB_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi

_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../mobsf/lib/mobsf.sh
source "${_LIB_DIR}/../mobsf/lib/mobsf.sh"
