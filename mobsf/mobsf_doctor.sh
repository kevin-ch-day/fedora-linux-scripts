#!/usr/bin/env bash
# mobsf_doctor.sh — MobSF stack readiness check
# Version: 0.2.0
#
# Run:
#   ./mobsf/mobsf_doctor.sh
#   ./mobsf/mobsf_doctor.sh --dynamic
#   ./mobsf/mobsf_doctor.sh --dynamic-only

set -euo pipefail

MOBSF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mobsf.sh
source "${MOBSF_DIR}/lib/mobsf.sh"

DYNAMIC=0
DYNAMIC_ONLY=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Checks podman tools, compose bundle, containers, and http://127.0.0.1:8080/login/

Options:
  --dynamic        Also run dynamic analysis readiness checks (ADB, host gateway)
  --dynamic-only   Skip static doctor; run dynamic checks only
  --help, -h       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --dynamic) DYNAMIC=1; shift ;;
    --dynamic-only) DYNAMIC_ONLY=1; shift ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

rc=0

if (( DYNAMIC_ONLY )); then
  mobsf_doctor_dynamic || rc=$?
  exit "${rc}"
fi

mobsf_doctor || rc=$?

if (( DYNAMIC )); then
  echo
  mobsf_doctor_dynamic || rc=$?
fi

exit "${rc}"
