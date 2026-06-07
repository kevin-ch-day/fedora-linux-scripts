#!/usr/bin/env bash
# android.sh — Android RE lane launcher (standalone menu + CLI shortcuts)
# Version: 0.1.0
#
# Run:
#   ./android/android.sh              Interactive menu
#   ./android/android.sh --doctor     Android-only doctor
#   ./android/android.sh verify all
#   ./android/android.sh verify apktool
#   ./android/android.sh --help

set -euo pipefail

ANDROID_LAUNCHER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${ANDROID_LAUNCHER_DIR}/.." && pwd)"

# shellcheck source=lib/menu.sh
source "${ANDROID_LAUNCHER_DIR}/lib/menu.sh"

usage() {
  cat <<EOF
Android RE lane launcher — core setup, RE tools, verify, doctors.

Usage: $(basename "$0") [command|option]

Options:
  --help, -h     Show this help
  --menu         Interactive menu (default)
  --doctor       Android research doctor (no MobSF)

Commands:
  verify TOOL    apktool | jadx | smali | dex2jar | all
  core           Run android_dev_core_setup.sh (sudo)
  research-doctor Full Android + MobSF doctor

Toolkit root: ${FEDORA_ROOT}
See: CONSOLIDATION.md
EOF
}

if [[ $# -eq 0 ]]; then
  android_menu_init "${FEDORA_ROOT}"
  android_main_menu
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --menu)
      android_menu_init "${FEDORA_ROOT}"
      android_main_menu
      exit 0
      ;;
    --doctor)
      exec bash "${ANDROID_LAUNCHER_DIR}/doctor_android_research.sh"
      ;;
    core)
      exec sudo bash "${ANDROID_LAUNCHER_DIR}/android_dev_core_setup.sh"
      ;;
    research-doctor)
      exec bash "${FEDORA_ROOT}/system/research_doctor.sh"
      ;;
    verify)
      shift
      [[ $# -gt 0 ]] || die "verify requires a tool (apktool|jadx|smali|dex2jar|all)"
      exec bash "${ANDROID_LAUNCHER_DIR}/verify_re_tool.sh" "$@"
      ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
done
