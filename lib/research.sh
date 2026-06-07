#!/usr/bin/env bash
# lib/research.sh — full research workstation doctor orchestration
# Version: 0.1.1
#
# Source from system/research_doctor.sh or launchers.
# Do not execute directly.

if [[ -n "${FEDORA_RESEARCH_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_RESEARCH_SH_LOADED=1

_RESEARCH_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_RESEARCH_LIB_DIR}/common.sh"

research_doctor_usage() {
  cat <<EOF
Usage: research_doctor.sh [--android-only] [--mobsf-only]

Runs readiness checks for the Android security research workstation:
  - Android core tools, ADB, RE toolchain (apktool, jadx, smali, dex2jar)
  - MobSF Podman stack (static analysis UI)

Also: ./fedora.sh --doctor

Exit code: 0 if all enabled checks pass, 1 otherwise.
EOF
}

# research_doctor_run FEDORA_ROOT DO_ANDROID DO_MOBSF
research_doctor_run() {
  local fedora_root="${1:?fedora root required}"
  local do_android="${2:-1}"
  local do_mobsf="${3:-1}"
  local rc=0

  if (( do_android )); then
    try_run bash "${fedora_root}/android/doctor_android_research.sh" || rc=1
    echo
  fi

  if (( do_mobsf )); then
    try_run bash "${fedora_root}/mobsf/mobsf_doctor.sh" || rc=1
  fi

  if (( do_android && do_mobsf )); then
    echo
    echo "============================================================"
    if (( rc == 0 )); then
      echo "Combined result: READY (Android + MobSF)"
    else
      echo "Combined result: ISSUES (see sections above)"
      echo "[HINT] Android: ./android/doctor_android_research.sh"
      echo "[HINT] MobSF:   sudo -E ./mobsf/mobsf_install.sh"
    fi
    echo "============================================================"
  fi

  return "${rc}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
