#!/usr/bin/env bash
# MobSF output regressions. Uses a mocked compose command; touches no containers.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${ROOT}/lib/common.sh"
_FEDORA_ROOT="${ROOT}"
# shellcheck source=../mobsf/lib/podman.sh
source "${ROOT}/mobsf/lib/podman.sh"

sandbox="$(mktemp -d)"
trap 'rm -rf "${sandbox}"' EXIT
LOG_FILE="${sandbox}/mobsf.log"

mobsf_pc() {
  printf 'Pulling image layers and compose internals\n'
}

rendered="$(mobsf_pc_action "Mock MobSF action" pull)"
[[ -z "${rendered}" ]] || {
  printf '[ERROR] successful Podman compose detail leaked to the terminal\n' >&2
  exit 1
}
grep -qF 'Pulling image layers and compose internals' "${LOG_FILE}" || {
  printf '[ERROR] captured Podman detail was not written to the MobSF log\n' >&2
  exit 1
}

printf '[OK]   successful Podman compose output is logged without leaking into the interface\n'
