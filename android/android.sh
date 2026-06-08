#!/usr/bin/env bash
# android.sh — Android RE & MobSF launcher (standalone menu + CLI shortcuts)
# Version: 0.1.2
#
# Run:
#   ./android/android.sh
#   ./fedora.sh --android
#   ./android/android.sh --doctor     Android workstation doctor
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
Android RE & MobSF launcher — core setup, RE tools, verification, and mobile analysis.

From main entry: ./fedora.sh → [6]  or  ./fedora.sh --android

Usage: $(basename "$0") [command|option]

Options:
  --help, -h     Show this help
  --menu         Interactive menu (default)
  --doctor       Android workstation doctor (no MobSF)

Commands:
  verify TOOL    apktool | jadx | smali | dex2jar | all
  core           Run android_dev_core_setup.sh (sudo)
  core-status    Show Android core status
  repair-node    Repair node/npm + apk-mitm tooling (sudo)
  research-doctor Full Android + MobSF doctor (rebuild finale)

Fedora doctor (entry points + Android): ./fedora.sh --doctor

Toolkit root: ${FEDORA_ROOT}
See: docs/GETTING-STARTED.md
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
      shift
      exec bash "${ANDROID_LAUNCHER_DIR}/doctor_android_research.sh" "$@"
      ;;
    core)
      shift
      exec sudo bash "${ANDROID_LAUNCHER_DIR}/android_dev_core_setup.sh" "$@"
      ;;
    core-status)
      shift
      exec bash "${ANDROID_LAUNCHER_DIR}/android_dev_core_setup.sh" --status "$@"
      ;;
    repair-node)
      shift
      exec sudo -E bash "${ANDROID_LAUNCHER_DIR}/android_dev_core_setup.sh" --repair-node "$@"
      ;;
    research-doctor)
      shift
      exec bash "${FEDORA_ROOT}/system/research_doctor.sh" "$@"
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
