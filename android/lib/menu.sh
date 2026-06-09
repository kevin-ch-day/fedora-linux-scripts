#!/usr/bin/env bash
# android/lib/menu.sh — Android RE & MobSF interactive menus (uses lib/menu.sh theme)
# Version: 0.3.1
#
# Standalone:  ./android/android.sh
# From main:   ./run.sh → [3] or ./run.sh --android
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

android_menu_header() {
  local title="$1"
  local subtitle="${2:-}"
  local page_title="${title}"
  menu_clear_screen
  theme_lane_banner "Android RE & MobSF" android
  if menu_is_submenu; then
    theme_meta_line "Path: $(menu_path_text)"
  else
    theme_meta_line "User: $(real_user) · Android tools: ~/.local/bin"
  fi
  menu_hr
  if [[ "${title}" == "Core setup" ]]; then
    page_title="Android core setup"
  fi
  theme_page_title "${page_title}"
  if [[ -n "${subtitle}" ]]; then
    theme_meta_line "${subtitle}"
  fi
}

android_menu_main_header() {
  local title="$1"
  local subtitle="${2:-}"
  menu_clear_screen
  theme_rule '═'
  if theme_use_color; then
    printf '%s◈ Android RE & MobSF%s\n' "${THEME_TITLE}" "${THEME_RESET}"
  else
    printf '◈ Android RE & MobSF\n'
  fi
  theme_meta_line "Android reverse engineering and mobile analysis"
  theme_meta_line "Path: $(menu_path_text)"
  menu_hr
  theme_page_title "${title}"
  if [[ -n "${subtitle}" ]]; then
    theme_meta_line "${subtitle}"
  fi
}

android_menu_init() {
  local fedora_root="${1:-${_FEDORA_ROOT}}"
  menu_init "Android RE & MobSF" "${fedora_root}" 0
  theme_set_lane android
  menu_set_header_fn android_menu_header
}

# ---------- Core setup ----------
_android_setup_items() {
  theme_section "Install"
  menu_item 1 "Install Android core tools" "packages · SDK cmdline-tools · pip tools"
  theme_section "Checks"
  menu_item 2 "Show Android core status" "versions · PATH · installed tools"
  menu_item_back
}

_android_setup_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) FEDORA_ANDROID_MENU_MODE=1 menu_run_sudo_env_script_scroll android/android_dev_core_setup.sh; menu_pause; return 0 ;;
    2) menu_run_script_scroll android/android_dev_core_setup.sh --status; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

android_menu_setup() {
  menu_loop "Core setup" "adb · sdkmanager · Android Studio · frida · objection · mitmproxy" \
    _android_setup_items _android_setup_dispatch
}

# ---------- RE installs ----------
_android_re_items() {
  theme_section "Quick picks"
  menu_item 5 "Install all four tools" "apktool · jadx · smali · dex2jar"
  menu_item 6 "Install all + verify all" "recommended after rebuild"
  menu_item 11 "Upgrade all" "re-download latest releases"
  theme_section "Individual install"
  menu_item 1 "Install apktool"
  menu_item 2 "Install jadx"
  menu_item 3 "Install smali/baksmali"
  menu_item 4 "Install dex2jar"
  theme_section "Install + verify one tool"
  menu_item 7 "Install + verify apktool"
  menu_item 8 "Install + verify jadx"
  menu_item 9 "Install + verify smali/baksmali"
  menu_item 10 "Install + verify dex2jar"
  theme_section "Upgrade one tool"
  menu_item 12 "Upgrade apktool"
  menu_item 13 "Upgrade jadx"
  menu_item 14 "Upgrade smali/baksmali"
  menu_item 15 "Upgrade dex2jar"
  menu_item_back
}

_android_re_install_verify() {
  local tool="$1"
  menu_run_script "android/android_re_install.sh" "${tool}"
  menu_run_script_scroll "android/verify_re_tool.sh" "${tool}"
}

_android_re_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script android/android_re_install.sh apktool; menu_pause; return 0 ;;
    2) menu_run_script android/android_re_install.sh jadx; menu_pause; return 0 ;;
    3) menu_run_script android/android_re_install.sh smali; menu_pause; return 0 ;;
    4) menu_run_script android/android_re_install.sh dex2jar; menu_pause; return 0 ;;
    5) menu_run_script android/android_re_install.sh all; menu_pause; return 0 ;;
    6)
      menu_run_script android/android_re_install.sh all
      menu_run_script_scroll android/verify_re_tool.sh all
      menu_pause
      return 0
      ;;
    7) _android_re_install_verify apktool; menu_pause; return 0 ;;
    8) _android_re_install_verify jadx; menu_pause; return 0 ;;
    9) _android_re_install_verify smali; menu_pause; return 0 ;;
    10) _android_re_install_verify dex2jar; menu_pause; return 0 ;;
    11) menu_run_script android/android_re_install.sh --upgrade all; menu_pause; return 0 ;;
    12) menu_run_script android/android_re_install.sh --upgrade apktool; menu_pause; return 0 ;;
    13) menu_run_script android/android_re_install.sh --upgrade jadx; menu_pause; return 0 ;;
    14) menu_run_script android/android_re_install.sh --upgrade smali; menu_pause; return 0 ;;
    15) menu_run_script android/android_re_install.sh --upgrade dex2jar; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

android_menu_re_install() {
  menu_loop "RE tool installs" "user-scope → ~/.local/" \
    _android_re_items _android_re_dispatch
}

# ---------- Verify ----------
_android_verify_items() {
  theme_section "Verify"
  menu_item 1 "Verify all RE tools" "recommended"
  menu_item 2 "Verify apktool"
  menu_item 3 "Verify jadx"
  menu_item 4 "Verify smali/baksmali"
  menu_item 5 "Verify dex2jar"
  theme_section "Debug"
  menu_item 6 "Debug smali env" "helpers/"
  menu_item_back
}

_android_verify_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script_scroll android/verify_re_tool.sh all; menu_pause; return 0 ;;
    2) menu_run_script_scroll android/verify_re_tool.sh apktool; menu_pause; return 0 ;;
    3) menu_run_script_scroll android/verify_re_tool.sh jadx; menu_pause; return 0 ;;
    4) menu_run_script_scroll android/verify_re_tool.sh smali; menu_pause; return 0 ;;
    5) menu_run_script_scroll android/verify_re_tool.sh dex2jar; menu_pause; return 0 ;;
    6) menu_run_script_scroll android/helpers/debug_bash_env_verify_smali.sh; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

android_menu_verify() {
  menu_loop "Verify" "check ~/.local installs" \
    _android_verify_items _android_verify_dispatch
}

# ---------- Diagnostics ----------
_android_doctors_items() {
  menu_item 1 "Android workstation doctor" "sdk · adb · re tools"
  menu_item 2 "Android + MobSF brief" "not ./mobsf.sh --doctor"
  menu_item 3 "ADB devices / status" "connected devices"
  menu_item_back
}

_android_doctors_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script_scroll android/doctor_android_research.sh; menu_pause; return 0 ;;
    2) menu_run_script_scroll android/doctor_android_research.sh --with-mobsf; menu_pause; return 0 ;;
    3) android_adb_status; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

android_menu_doctors() {
  menu_loop "Doctors & ADB" "matrix: docs/GETTING-STARTED.md#doctor-matrix-no-double-runs" \
    _android_doctors_items _android_doctors_dispatch
}

_android_main_items() {
  theme_section "Setup"
  menu_item 1 "Install Android core tools" "adb · sdkmanager · Python tools · Android Studio"
  menu_item 2 "Install APK RE tools" "apktool · jadx · smali · dex2jar"
  theme_section "Checks"
  menu_item 3 "Verify Android RE environment" "adb · java · sdkmanager · frida · objection"
  menu_item 4 "ADB and device checks" "devices · udev · permissions"
  theme_section "Mobile analysis"
  menu_item 5 "MobSF stack" "setup · start · stop · status"
  theme_section "Maintenance"
  menu_item 6 "Repair Node/npm tooling" "npm · node · apk-mitm"
  theme_section "Docs"
  menu_item 7 "Lane guide" "android/README.md"
  menu_item_lane_exit
}

_android_main_dispatch() {
  case "$1" in
    0) menu_lane_handle_main_exit ;;
    1) android_menu_setup; return 0 ;;
    2) android_menu_re_install; return 0 ;;
    3) menu_run_script_scroll android/doctor_android_research.sh; menu_pause; return 0 ;;
    4) android_adb_status; menu_pause; return 0 ;;
    5) menu_run_script mobsf.sh; menu_pause; return 0 ;;
    6) FEDORA_ANDROID_MENU_MODE=1 menu_run_sudo_env_script_scroll android/android_dev_core_setup.sh --repair-node; menu_pause; return 0 ;;
    7) menu_open_file "${MENU_ROOT}/android/README.md"; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

android_main_menu() {
  local prev_header="${MENU_HEADER_FN}"
  menu_set_header_fn android_menu_main_header
  menu_loop "Android RE & MobSF" "sdk · adb · apk tools · dynamic tools · mobsf" \
    _android_main_items _android_main_dispatch
  menu_set_header_fn "${prev_header}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
