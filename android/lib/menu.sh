#!/usr/bin/env bash
# android/lib/menu.sh — Android lane interactive menus (uses lib/menu.sh theme)
# Version: 0.2.1
#
# Standalone:  ./android/android.sh
# From fedora: ./fedora.sh → [3] execs ./android/android.sh
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
  menu_clear_screen
  echo "${CYAN}${BOLD}${MENU_APP_NAME}${RESET}  ${DIM}RE workstation · $(real_user)${RESET}"
  echo "Home: $(real_home)  ·  RE tools: ~/.local/bin"
  menu_hr
  menu_print_breadcrumb
  echo "${BOLD}${title}${RESET}"
  [[ -n "${subtitle}" ]] && echo "${DIM}${subtitle}${RESET}"
}

android_menu_init() {
  local fedora_root="${1:-${_FEDORA_ROOT}}"
  menu_init "Android RE" "${fedora_root}"
  menu_set_header_fn android_menu_header
}

# ---------- Core setup ----------
_android_setup_items() {
  menu_item 1 "Install Android core tools (sudo)"
  menu_item_back
}

_android_setup_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_sudo_script android/android_dev_core_setup.sh; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

android_menu_setup() {
  menu_loop "Setup" "core packages · SDK · pip tools" \
    _android_setup_items _android_setup_dispatch
}

# ---------- RE installs ----------
_android_re_items() {
  menu_item 1 "Install apktool"
  menu_item 2 "Install jadx"
  menu_item 3 "Install smali/baksmali"
  menu_item 4 "Install dex2jar"
  menu_item 5 "Install all four (sequential)"
  menu_item 6 "Install all + verify all"
  menu_item 7 "Install + verify apktool"
  menu_item 8 "Install + verify jadx"
  menu_item 9 "Install + verify smali/baksmali"
  menu_item 10 "Install + verify dex2jar"
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
    *) return 2 ;;
  esac
}

android_menu_re_install() {
  menu_loop "RE tool installs" "user-scope → ~/.local/" \
    _android_re_items _android_re_dispatch
}

# ---------- Verify ----------
_android_verify_items() {
  menu_item 1 "Verify all RE tools"
  menu_item 2 "Verify apktool"
  menu_item 3 "Verify jadx"
  menu_item 4 "Verify smali/baksmali"
  menu_item 5 "Verify dex2jar"
  menu_item 6 "Debug smali env (helpers/)"
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
  menu_item 1 "Android research doctor (SDK · ADB · pip tools)"
  menu_item 2 "ADB devices / status"
  menu_item_back
}

_android_doctors_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script_scroll android/doctor_android_research.sh; menu_pause; return 0 ;;
    2) android_adb_status; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

android_menu_doctors() {
  menu_loop "Doctors & ADB" "full stack doctor: System lane [4]" \
    _android_doctors_items _android_doctors_dispatch
}

_android_main_items() {
  menu_item 1 "Setup"
  menu_item 2 "RE tool installs"
  menu_item 3 "Verify"
  menu_item 4 "Doctors & ADB"
  menu_item 5 "Lane guide (README)"
  menu_item_lane_exit
}

_android_main_dispatch() {
  case "$1" in
    0) menu_lane_handle_main_exit ;;
    1) android_menu_setup; return 0 ;;
    2) android_menu_re_install; return 0 ;;
    3) android_menu_verify; return 0 ;;
    4) android_menu_doctors; return 0 ;;
    5) menu_open_file "${MENU_ROOT}/android/README.md"; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

android_main_menu() {
  menu_loop "Android menu" "security research · reverse engineering" \
    _android_main_items _android_main_dispatch
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
