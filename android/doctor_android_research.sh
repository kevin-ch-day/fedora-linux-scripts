#!/usr/bin/env bash
# doctor_android_research.sh — Android research workstation readiness check
# Version: 0.2.1
#
# Run:
#   ./doctor_android_research.sh
#   ./doctor_android_research.sh --with-mobsf

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${_SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/android.sh
source "${_SCRIPT_DIR}/../lib/android.sh"

WITH_MOBSF=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-mobsf) WITH_MOBSF=1; shift ;;
    --help|-h)
      echo "Usage: $(basename "$0") [--with-mobsf]"
      echo "Checks core tooling (Java, Frida, ADB), RE tools, and reports READY/ISSUES."
      echo "  --with-mobsf  Include brief MobSF stack status"
      exit 0
      ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

rc=0
doctor_android_research || rc=1

if (( WITH_MOBSF )); then
  # shellcheck source=../mobsf/lib/mobsf.sh
  source "${FEDORA_ROOT}/mobsf/lib/mobsf.sh"
  echo
  echo "== MobSF (optional) =="
  mobsf_doctor_brief || rc=1
  echo
  echo "============================================================"
  if (( rc == 0 )); then
    echo "Combined result: READY (Android + MobSF)"
  else
    echo "Combined result: ISSUES FOUND"
  fi
  echo "============================================================"
fi

exit "${rc}"
