#!/usr/bin/env bash
# Profile safety regressions. No installs, sudo, or host writes.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/profiles.sh
source "${ROOT}/lib/profiles.sh"
TESTS=0

pass() {
  TESTS=$((TESTS + 1))
  printf '[OK]   %s\n' "$1"
}

fail() {
  printf '[ERROR] %s\n' "$1" >&2
  exit 1
}

research_steps="$(profile_iter_steps research)"
grep -q $'Podman + KVM\tdev/fedora_container_kvm_setup.sh\tsudo\t--no-docker' \
  <<< "${research_steps}" ||
  fail "research profile is not explicitly Podman-first"
pass "research profile is explicitly Podman-first"

dev_steps="$(profile_iter_steps dev-full)"
grep -q -- '--no-docker' <<< "${dev_steps}" ||
  fail "developer profile can implicitly install Docker"
pass "developer profile keeps Docker opt-in"

mariadb_steps="$(profile_iter_steps mariadb-no-start)"
grep -q -- '--mariadb-only --no-start' <<< "${mariadb_steps}" ||
  fail "MariaDB package-only profile can start the service"
pass "MariaDB package-only profile leaves service state untouched"

profile_requires_service_ack web-stack ||
  fail "web-stack is missing its service-start acknowledgement"
if profile_requires_service_ack mariadb-no-start; then
  fail "mariadb-no-start incorrectly requires a service-start acknowledgement"
fi
pass "service-start acknowledgement is scoped to web-stack"

if bash "${ROOT}/install.sh" web-stack --yes >/dev/null 2>&1; then
  fail "web-stack --yes bypassed service-start acknowledgement"
fi
pass "web-stack auto mode requires explicit service-start acknowledgement"

dry_output="$(bash "${ROOT}/install.sh" web-stack --yes --dry-run)" ||
  fail "web-stack dry-run was incorrectly blocked"
grep -q 'Changes:.*none' <<< "${dry_output}" ||
  fail "profile dry-run is presented as a completed installation"
pass "web-stack dry-run remains non-mutating and available"

grep -q '^INSTALL_DOCKER=0$' "${ROOT}/dev/fedora_container_kvm_setup.sh" ||
  fail "combined infrastructure installer does not default to Podman"
pass "combined infrastructure installer defaults to Podman"

printf '[OK]   Profile safety regressions passed (%s)\n' "${TESTS}"
