#!/usr/bin/env bash
# Health severity regression tests. No host writes.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/health_snapshot.sh
source "${ROOT}/lib/health_snapshot.sh"
GIB=$((1024 * 1024 * 1024))
TESTS=0

assert_status() {
  local expected="$1" actual="$2" label="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    printf '[ERROR] %s: expected %s, got %s\n' "${label}" "${expected}" "${actual}" >&2
    exit 1
  fi
  TESTS=$((TESTS + 1))
  printf '[OK]   %s\n' "${label}"
}

assert_status OK "$(health_snapshot_ram_status "$((7 * GIB))" "$((16 * GIB))")" \
  "healthy proportional RAM availability is not a warning"
assert_status WARN "$(health_snapshot_ram_status "$((3 * GIB))" "$((16 * GIB))")" \
  "low RAM availability produces a warning"
assert_status BAD "$(health_snapshot_ram_status "$((1 * GIB))" "$((16 * GIB))")" \
  "critical RAM availability produces a failure"
assert_status NOTE "$(health_snapshot_swap_status "$((2 * GIB))" "$((8 * GIB))" zram)" \
  "normal compressed zram use is informational"
assert_status WARN "$(health_snapshot_swap_status "$((7 * GIB))" "$((8 * GIB))" zram)" \
  "high zram pressure produces a warning"
assert_status WARN "$(health_snapshot_swap_status "$((5 * GIB))" "$((8 * GIB))" disk)" \
  "high disk swap use produces a warning"
assert_status OK "$(health_snapshot_worst_status OK NOTE OK)" \
  "informational observations do not downgrade overall health"

printf '[OK]   Health snapshot regressions passed (%s)\n' "${TESTS}"
