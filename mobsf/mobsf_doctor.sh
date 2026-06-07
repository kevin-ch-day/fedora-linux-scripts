#!/usr/bin/env bash
# mobsf_doctor.sh — MobSF stack readiness check
# Version: 0.1.0
#
# Run: ./mobsf/mobsf_doctor.sh [--help]

set -euo pipefail

MOBSF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mobsf.sh
source "${MOBSF_DIR}/lib/mobsf.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      echo "Usage: $(basename "$0")"
      echo "Checks podman tools, compose bundle, containers, and http://127.0.0.1:8080/login/"
      exit 0
      ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

mobsf_doctor
