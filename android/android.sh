#!/usr/bin/env bash
# android.sh — Android RE tools launcher (standalone menu + CLI shortcuts)
# Version: 0.2.0
#
# Run:
#   ./android/android.sh
#   ./run.sh --android
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
Android RE tools launcher — flexible core presets, APK tools, verification, and ADB checks.
MobSF stack (separate): ./mobsf.sh

From main entry: ./run.sh --android

Usage: $(basename "$0") [command|option]

Options:
  --help, -h     Show this help
  --menu         Interactive menu (default)
  --doctor       Android workstation doctor (no MobSF)

Commands:
  verify TOOL    apktool | jadx | smali | dex2jar | all
  core [PRESET]  Install minimal | standard | full core (sudo; default standard)
  plan [PRESET]  Preview resolved core capabilities; no changes
  core-status    Show Android core status
  apk-install [TOOL]
                 Install apktool | jadx | smali | dex2jar | all (default all)
  apk-upgrade [TOOL]
                 Re-download one/all APK tools (default all)
  repair-node    Repair node/npm + apk-mitm tooling (sudo)
  research-doctor Full Android + MobSF doctor (rebuild finale)

Fedora doctor (entry points + Android): ./run.sh --doctor

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
      core_args=()
      if [[ "${1:-}" =~ ^(minimal|standard|full)$ ]]; then
        core_args+=(--preset "$1")
        shift
      fi
      exec sudo -E bash "${ANDROID_LAUNCHER_DIR}/android_dev_core_setup.sh" "${core_args[@]}" "$@"
      ;;
    plan)
      shift
      plan_preset="${1:-standard}"
      if [[ "${plan_preset}" =~ ^(minimal|standard|full)$ ]]; then
        if (($# > 0)); then
          shift
        fi
      else
        plan_preset="standard"
      fi
      exec bash "${ANDROID_LAUNCHER_DIR}/android_dev_core_setup.sh" \
        --preset "${plan_preset}" --plan "$@"
      ;;
    core-status)
      shift
      exec bash "${ANDROID_LAUNCHER_DIR}/android_dev_core_setup.sh" --status "$@"
      ;;
    repair-node)
      shift
      exec sudo -E bash "${ANDROID_LAUNCHER_DIR}/android_dev_core_setup.sh" --repair-node "$@"
      ;;
    apk-install)
      shift
      apk_tool="${1:-all}"
      if (($# > 0)); then
        shift
      fi
      (($# == 0)) || die "apk-install accepts one tool"
      exec bash "${ANDROID_LAUNCHER_DIR}/android_re_install.sh" "${apk_tool}"
      ;;
    apk-upgrade)
      shift
      apk_tool="${1:-all}"
      if (($# > 0)); then
        shift
      fi
      (($# == 0)) || die "apk-upgrade accepts one tool"
      exec bash "${ANDROID_LAUNCHER_DIR}/android_re_install.sh" --upgrade "${apk_tool}"
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
