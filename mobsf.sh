#!/usr/bin/env bash
# mobsf.sh — Root-level MobSF stack entry (delegates to mobsf/mobsf.sh)
# Version: 0.1.0
#
# MobSF has its own lifecycle (Podman stack, compose, reset, doctor) and is
# intentionally separate from ./run.sh.

set -euo pipefail

MOBSF_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MOBSF_LAUNCHER="${MOBSF_ROOT}/mobsf/mobsf.sh"

if [[ ! -f "${MOBSF_LAUNCHER}" ]]; then
  printf '[ERROR] MobSF launcher not found: %s\n' "${MOBSF_LAUNCHER}" >&2
  exit 1
fi

if [[ ! -x "${MOBSF_LAUNCHER}" ]]; then
  printf '[ERROR] MobSF launcher is not executable: %s\n' "${MOBSF_LAUNCHER}" >&2
  exit 1
fi

exec bash "${MOBSF_LAUNCHER}" "$@"
