#!/usr/bin/env bash
# dev/lib/menu.sh — Dev workstation lane menus (uses lib/menu.sh theme)
# Version: 0.2.0
#
# Standalone:  ./dev/dev.sh
# From fedora: ./fedora.sh → [2] execs ./dev/dev.sh
#
# Do not execute directly.

if [[ -n "${FEDORA_DEV_MENU_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_DEV_MENU_LOADED=1

_DEV_MENU_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
_FEDORA_ROOT="$(cd -- "${_DEV_MENU_LIB_DIR}/../.." && pwd)"

# shellcheck source=../../lib/services.sh
source "${_FEDORA_ROOT}/lib/services.sh"
# shellcheck source=../../lib/menu.sh
source "${_FEDORA_ROOT}/lib/menu.sh"

dev_menu_header() {
  local title="$1"
  local subtitle="${2:-}"
  menu_clear_screen
  echo "${CYAN}${BOLD}${MENU_APP_NAME}${RESET}  ${DIM}workstation · $(real_user)${RESET}"
  echo "Toolkit: ${MENU_ROOT}"
  menu_hr
  menu_print_breadcrumb
  echo "${BOLD}${title}${RESET}"
  [[ -n "${subtitle}" ]] && echo "${DIM}${subtitle}${RESET}"
}

dev_menu_init() {
  local fedora_root="${1:-${_FEDORA_ROOT}}"
  menu_init "Dev Workstation" "${fedora_root}"
  menu_set_header_fn dev_menu_header
}

# ---------- Workstation ----------
_dev_workstation_items() {
  menu_item 1 "Git setup (prompts for name/email)"
  menu_item 2 "Git config status (read-only)"
  menu_item 3 "Install VS Code (sudo)"
  menu_item 4 "Desktop: Cinnamon + fallbacks (sudo)"
  menu_item 5 "Desktop status"
  menu_item_back
}

_dev_workstation_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script dev/git_setup.sh; menu_pause; return 0 ;;
    2) menu_run_script_scroll dev/git_setup.sh --status; menu_pause; return 0 ;;
    3) menu_run_sudo_script dev/install_vscode.sh; menu_pause; return 0 ;;
    4) menu_run_sudo_script dev/desktop_setup.sh; menu_pause; return 0 ;;
    5) menu_run_script dev/desktop_setup.sh --status; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

dev_menu_workstation() {
  menu_loop "Workstation" "git · editor · desktop · set GIT_NAME/GIT_EMAIL to skip prompts" \
    _dev_workstation_items _dev_workstation_dispatch
}

# ---------- Infrastructure ----------
_dev_infra_items() {
  menu_item 1 "Containers + KVM (sudo)"
  menu_item 2 "Research service status"
  menu_item_back
}

_dev_infra_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_sudo_script dev/fedora_container_kvm_setup.sh; menu_pause; return 0 ;;
    2) services_status_research_stack; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

dev_menu_infrastructure() {
  menu_loop "Infrastructure" "podman · docker · libvirt" \
    _dev_infra_items _dev_infra_dispatch
}

# ---------- Web stack ----------
_dev_web_items() {
  menu_item 1 "LAMP + Python (sudo, localhost)"
  menu_item 2 "phpMyAdmin (sudo, localhost default)"
  menu_item 3 "Web stack doctor"
  menu_item 4 "Remove public info.php (if created)"
  menu_item_back
}

_dev_web_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_sudo_script dev/lamp_python_setup.sh; menu_pause; return 0 ;;
    2) menu_run_sudo_script dev/phpmyadmin_setup.sh; menu_pause; return 0 ;;
    3) menu_run_script_scroll dev/web_stack_doctor.sh; menu_pause; return 0 ;;
    4) menu_run_sudo_script dev/lamp_python_setup.sh --remove-info-php; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

dev_menu_web_stack() {
  menu_loop "Web stack" "Apache · MariaDB · PHP · phpMyAdmin" \
    _dev_web_items _dev_web_dispatch
}

# ---------- Help & docs ----------
_dev_help_items() {
  menu_item 1 "GETTING-STARTED.md"
  menu_item 2 "README.md (toolkit index)"
  menu_item 3 "dev/README.md (lane guide)"
  menu_item_back
}

_dev_help_dispatch() {
  local doc=""
  case "$1" in
    0) return 1 ;;
    1) doc="${MENU_ROOT}/GETTING-STARTED.md" ;;
    2) doc="${MENU_ROOT}/README.md" ;;
    3) doc="${MENU_ROOT}/dev/README.md" ;;
    *) return 2 ;;
  esac
  menu_open_file "${doc}"
  menu_pause
  return 0
}

dev_menu_help() {
  menu_loop "Help & docs" "guides · dev lane" \
    _dev_help_items _dev_help_dispatch
}

# ---------- Main dev menu ----------
_dev_main_items() {
  menu_item 1 "Workstation"
  menu_item 2 "Infrastructure"
  menu_item 3 "Web stack"
  menu_item 4 "Help & docs"
  menu_item_lane_exit
}

_dev_main_dispatch() {
  case "$1" in
    0) menu_lane_handle_main_exit ;;
    1) dev_menu_workstation; return 0 ;;
    2) dev_menu_infrastructure; return 0 ;;
    3) dev_menu_web_stack; return 0 ;;
    4) dev_menu_help; return 0 ;;
    *) return 2 ;;
  esac
}

dev_main_menu() {
  menu_loop "Dev menu" "tools · containers · LAMP" \
    _dev_main_items _dev_main_dispatch
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
