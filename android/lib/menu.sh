#!/usr/bin/env bash
# android/lib/menu.sh — Android RE tools interactive menus (uses lib/menu.sh theme)
# Version: 0.4.0
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

android_menu_header() {
  local title="$1"
  local subtitle="${2:-}"
  local page_title="${title}"
  menu_clear_screen
  theme_lane_banner "Android RE tools" android
  if menu_is_submenu; then
    theme_meta_line "PATH / $(menu_path_text)"
  else
    theme_meta_line "USER / $(real_user) · TOOLS / ~/.local/bin"
  fi
  menu_hr
  theme_page_title "${page_title}"
  if [[ -n "${subtitle}" ]]; then
    theme_meta_line "${subtitle}"
  fi
}

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
  menu_set_header_fn android_menu_header
}

_android_run_core_preset() {
  local preset="$1"
  local description="$2"

  warn "${description}"
  info "Preview without changes: ./android/android.sh plan ${preset}"
  if confirm "Install the ${preset} Android core preset?"; then
    FEDORA_ANDROID_MENU_MODE=1 \
      menu_run_sudo_env_script_scroll android/android_dev_core_setup.sh --preset "${preset}"
  else
    info "Android ${preset} install cancelled"
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

# ---------- RE installs ----------
_android_re_install_one_items() {
  menu_item 1 "Install apktool"
  menu_item 2 "Install jadx"
  menu_item 3 "Install smali/baksmali"
  menu_item 4 "Install dex2jar"
  menu_item_back
}

_android_re_install_one_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script android/android_re_install.sh apktool; menu_pause; return 0 ;;
    2) menu_run_script android/android_re_install.sh jadx; menu_pause; return 0 ;;
    3) menu_run_script android/android_re_install.sh smali; menu_pause; return 0 ;;
    4) menu_run_script android/android_re_install.sh dex2jar; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

android_menu_re_install_one() {
  menu_loop "Install one RE tool" "user-scope → ~/.local/" \
    _android_re_install_one_items _android_re_install_one_dispatch
}

_android_re_upgrade_one_items() {
  menu_item 1 "Upgrade apktool"
  menu_item 2 "Upgrade jadx"
  menu_item 3 "Upgrade smali/baksmali"
  menu_item 4 "Upgrade dex2jar"
  menu_item_back
}

_android_re_upgrade_one_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script android/android_re_install.sh --upgrade apktool; menu_pause; return 0 ;;
    2) menu_run_script android/android_re_install.sh --upgrade jadx; menu_pause; return 0 ;;
    3) menu_run_script android/android_re_install.sh --upgrade smali; menu_pause; return 0 ;;
    4) menu_run_script android/android_re_install.sh --upgrade dex2jar; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

android_menu_re_upgrade_one() {
  menu_loop "Upgrade one RE tool" "re-download latest release" \
    _android_re_upgrade_one_items _android_re_upgrade_one_dispatch
}

_android_re_items() {
  theme_section "Recommended"
  menu_item 1 "Install all four tools" "apktool · jadx · smali · dex2jar"
  menu_item 2 "Verify all installed tools" "read-only · no duplicate downloads"
  menu_item 3 "Upgrade all" "re-download latest releases"
  theme_section "One tool"
  menu_item 4 "Install one tool…" "apktool · jadx · smali · dex2jar"
  menu_item 5 "Upgrade one tool…" "pick a single tool"
  menu_item_back
}

_android_re_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script android/android_re_install.sh all; menu_pause; return 0 ;;
    2) menu_run_script_scroll android/verify_re_tool.sh all; menu_pause; return 0 ;;
    3) menu_run_script android/android_re_install.sh --upgrade all; menu_pause; return 0 ;;
    4) android_menu_re_install_one; return 0 ;;
    5) android_menu_re_upgrade_one; return 0 ;;
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
  menu_item 1 "Verify all RE tools" "recommended after install"
  theme_section "One tool"
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

_android_advanced_items() {
  theme_section "Inspect — no changes"
  menu_item 1 "Show core capability status" "versions · PATH · installed tools"
  menu_item 2 "Plan minimal/headless core" "Java · adb · SDK CLI"
  menu_item 3 "Plan standard core" "recommended workstation"
  menu_item 4 "Plan full core" "standard + Node/npm · apk-mitm"
  theme_section "APK tool maintenance"
  menu_item 5 "Upgrade all APK RE tools" "re-download latest releases"
  menu_item 6 "Install or upgrade selected tools…" "per-tool choices"
  menu_item 7 "Verify or debug selected tools…" "per-tool checks"
  theme_section "Optional maintenance"
  menu_item 8 "Repair Android SDK shell PATH" "~/.bashrc managed block only · no sudo"
  menu_item 9 "Repair Node/npm tooling" "isolated · apk-mitm only"
  menu_item 10 "Android + MobSF brief" "read-only combined doctor"
  menu_item_back
}

_android_advanced_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script_scroll android/android_dev_core_setup.sh --status; menu_pause; return 0 ;;
    2) menu_run_script_scroll android/android_dev_core_setup.sh --preset minimal --plan; menu_pause; return 0 ;;
    3) menu_run_script_scroll android/android_dev_core_setup.sh --preset standard --plan; menu_pause; return 0 ;;
    4) menu_run_script_scroll android/android_dev_core_setup.sh --preset full --plan; menu_pause; return 0 ;;
    5)
      warn "This re-downloads all four user-scoped APK RE tool releases."
      if confirm "Upgrade all APK RE tools?"; then
        menu_run_script_scroll android/android_re_install.sh --upgrade all
      else
        info "APK RE tool upgrade cancelled"
      fi
      menu_pause
      return 0
      ;;
    6) android_menu_re_install; return 0 ;;
    7) android_menu_verify; return 0 ;;
    8)
      warn "This rewrites only the managed Android SDK PATH block in ~/.bashrc."
      if confirm "Repair the Android SDK shell PATH block?"; then
        menu_run_script_scroll android/android_dev_core_setup.sh --repair-shell
      else
        info "Android SDK shell PATH repair cancelled"
      fi
      menu_pause
      return 0
      ;;
    9)
      warn "This installs or repairs Node/npm and the optional apk-mitm package only."
      if confirm "Continue with isolated Node/npm repair?"; then
        FEDORA_ANDROID_MENU_MODE=1 \
          menu_run_sudo_env_script_scroll android/android_dev_core_setup.sh --repair-node
      else
        info "Node/npm repair cancelled"
      fi
      menu_pause
      return 0
      ;;
    10) menu_run_script_scroll android/doctor_android_research.sh --with-mobsf; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

android_menu_advanced() {
  menu_loop "Advanced Android tools" "plans · per-tool install/verify · optional maintenance" \
    _android_advanced_items _android_advanced_dispatch
}

_android_main_items() {
  theme_section "Quick setup"
  menu_item_lane 1 android "Install complete Android RE workstation" "guided · standard core + APK tools + verify"
  menu_item_lane 2 android "Install standard core only" "desktop · SDK · Python security tools"
  menu_item_lane 3 android "Install APK RE tools only" "apktool · jadx · smali · dex2jar"
  menu_item_lane 4 android "Install minimal/headless core" "Java · adb/fastboot · SDK CLI"
  theme_section "Checks"
  menu_item 5 "Android workstation doctor" "one readiness report · core + APK tools"
  menu_item 6 "ADB and device checks" "devices · udev · permissions"
  theme_section "More"
  menu_item 7 "Advanced tools and plans…" "customize · upgrade · per-tool checks"
  theme_section "Mobile analysis"
  menu_item 8 "Open MobSF stack" "separate lifecycle · ./mobsf.sh"
  theme_section "Docs"
  menu_item 9 "Lane guide" "presets · commands · troubleshooting"
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
    2)
      _android_run_core_preset standard \
        "Standard installs Java, adb, SDK CLI, Python security tools, Wireshark, Android Studio, and a managed PATH block."
      return 0
      ;;
    3) _android_install_re_all; return 0 ;;
    4)
      _android_run_core_preset minimal \
        "Minimal is intended for headless, low-resource, or device-only hosts; it skips Studio, Python tools, Wireshark, and Node."
      return 0
      ;;
    5) menu_run_script_scroll android/doctor_android_research.sh; menu_pause; return 0 ;;
    6) android_adb_status; menu_pause; return 0 ;;
    7) android_menu_advanced; return 0 ;;
    8) menu_run_script mobsf.sh; menu_pause; return 0 ;;
    9) menu_open_file "${MENU_ROOT}/android/README.md"; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

android_main_menu() {
  local prev_header="${MENU_HEADER_FN}"
  menu_set_header_fn android_menu_main_header
  menu_loop "Android RE tools" "choose a result · common installs run directly" \
    _android_main_items _android_main_dispatch
  menu_set_header_fn "${prev_header}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
