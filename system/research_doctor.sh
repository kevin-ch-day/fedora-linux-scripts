#!/usr/bin/env bash
# research_doctor.sh — Full research workstation doctor (Android RE + MobSF)
# Version: 0.2.0 — orchestration in lib/research.sh
#
# Run:
#   ./system/research_doctor.sh
#   ./system/research_doctor.sh --android-only
#   ./system/research_doctor.sh --mobsf-only

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${_SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/research.sh
source "${FEDORA_ROOT}/lib/research.sh"

DO_ANDROID=1
DO_MOBSF=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --android-only) DO_MOBSF=0; shift ;;
    --mobsf-only) DO_ANDROID=0; shift ;;
    --help|-h) research_doctor_usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

research_doctor_run "${FEDORA_ROOT}" "${DO_ANDROID}" "${DO_MOBSF}"
