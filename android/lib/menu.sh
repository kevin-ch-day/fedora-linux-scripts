#!/usr/bin/env bash
# android/lib/menu.sh — Android RE tools interactive menus (uses lib/menu.sh theme)
# Version: 0.5.0
#
# Standalone:  ./android/android.sh
# From main:   ./run.sh → Install workstation → Android RE tools
# Direct:      ./run.sh --android
#
# Do not execute directly.

if [[ -n "${FEDORA_ANDROID_MENU_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_ANDROID_MENU_LOADED=1

_ANDROID_MENU_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
_FEDORA_ROOT="$(cd -- "${_ANDROID_MENU_LIB_DIR}/../.." && pwd)"

# shellcheck source=../../lib/android.sh
source "${_FEDORA_ROOT}/lib/android.sh"
# shellcheck source=../../lib/menu.sh
source "${_FEDORA_ROOT}/lib/menu.sh"

android_menu_main_header() {
  local title="$1"
  local subtitle="${2:-}"
  menu_clear_screen
  theme_lane_banner "Android RE tools" android \
    "Android reverse engineering · MobSF: ./mobsf.sh (separate)"
  theme_meta_line "PATH / $(menu_path_text)"
  menu_hr
  theme_page_title "${title}"
  if [[ -n "${subtitle}" ]]; then
    theme_meta_line "${subtitle}"
  fi
}

android_menu_init() {
  local fedora_root="${1:-${_FEDORA_ROOT}}"
  menu_init "Android RE tools" "${fedora_root}" 0
  theme_set_lane android
  menu_set_header_fn android_menu_main_header
}

_android_install_standard_core() {
  warn "Installs Java, adb, SDK CLI, Python security tools, Wireshark, Android Studio, and a managed PATH block."
  info "Preview without changes: ./android/android.sh plan standard"
  if confirm "Install the standard Android core preset?"; then
    FEDORA_ANDROID_MENU_MODE=1 \
      menu_run_sudo_env_script_scroll android/android_dev_core_setup.sh --preset standard
  else
    info "Android standard install cancelled"
  fi
  menu_pause
}

_android_install_re_all() {
  warn "Downloads apktool, jadx, smali/baksmali, and dex2jar into ~/.local."
  if confirm "Install all APK reverse-engineering tools?"; then
    menu_run_script_scroll android/android_re_install.sh all
  else
    info "APK RE tool install cancelled"
  fi
  menu_pause
}

_android_main_items() {
  theme_section "Install"
  menu_item_lane 1 android "Install complete Android RE workstation" "guided · confirms system and user changes"
  menu_item_lane 2 android "Install standard core only" "sudo · Studio · SDK · Python security tools"
  menu_item_lane 3 android "Install APK RE tools only" "user scope · ~/.local · four tools"
  theme_section "Inspect — no changes"
  menu_item 4 "Android workstation doctor" "readiness · versions · SDK · APK tools"
  menu_item 5 "ADB and device checks" "devices · udev · permissions"
  theme_section "Related"
  menu_item 6 "Open MobSF stack" "separate mobile-analysis lifecycle"
  menu_item 7 "Commands and troubleshooting" "advanced installs · upgrades · repairs"
  menu_item_lane_exit
}

_android_main_dispatch() {
  case "$1" in
    0) menu_lane_handle_main_exit ;;
    1)
      FEDORA_FROM_MENU=1 menu_run_script_scroll install.sh android-re
      menu_pause
      return 0
      ;;
    2) _android_install_standard_core; return 0 ;;
    3) _android_install_re_all; return 0 ;;
    4) menu_run_script_scroll android/doctor_android_research.sh; menu_pause; return 0 ;;
    5) android_adb_status; menu_pause; return 0 ;;
    6) menu_run_script mobsf.sh; menu_pause; return 0 ;;
    7) menu_open_file "${MENU_ROOT}/android/README.md"; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

android_main_menu() {
  local prev_header="${MENU_HEADER_FN}"
  menu_set_header_fn android_menu_main_header
  menu_loop "Android RE tools" "install · inspect · analyze" \
    _android_main_items _android_main_dispatch
  menu_set_header_fn "${prev_header}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
