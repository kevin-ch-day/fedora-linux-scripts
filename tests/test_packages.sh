#!/usr/bin/env bash
# Package output regressions. Uses a mocked sudo/dnf path; changes no packages.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/packages.sh
source "${ROOT}/lib/packages.sh"

sandbox="$(mktemp -d)"
trap 'rm -rf "${sandbox}"' EXIT
FEDORA_PACKAGE_LOG="${sandbox}/package-transactions.log"

sudo() {
  if [[ "${1:-}" == dnf ]]; then
    printf 'Updating and loading repositories:\n'
    printf 'Package transaction detail that belongs in the log\n'
    return 0
  fi
  return 1
}

rendered="$(_dnf_run "Mock package transaction failed" install example)"
[[ -z "${rendered}" ]] || {
  printf '[ERROR] successful DNF detail leaked to the terminal\n' >&2
  exit 1
}
grep -qF 'Package transaction detail that belongs in the log' "${FEDORA_PACKAGE_LOG}" || {
  printf '[ERROR] captured DNF detail was not written to the package log\n' >&2
  exit 1
}

noisy_dependency_tool() {
  printf 'Downloading dependency metadata and wheels\n'
}

rendered="$(pkg_run_captured "Mock dependency command failed" pip noisy_dependency_tool)"
[[ -z "${rendered}" ]] || {
  printf '[ERROR] successful dependency-command detail leaked to the terminal\n' >&2
  exit 1
}
grep -qF 'Downloading dependency metadata and wheels' "${FEDORA_PACKAGE_LOG}" || {
  printf '[ERROR] captured dependency detail was not written to the package log\n' >&2
  exit 1
}

printf '[OK]   package-manager output is logged without leaking into the interface\n'
