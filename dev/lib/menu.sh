#!/usr/bin/env bash
# dev/lib/menu.sh — Dev workstation lane menus (uses lib/menu.sh theme)
# Version: 0.3.0
#
# Standalone:  ./dev/dev.sh
# From main:   ./fedora.sh → [2] or ./fedora.sh --dev
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
  theme_banner "Development lane"
  theme_meta_line "Host: $(hostname) · User: $(real_user)"
  theme_meta_line "Root: ${MENU_ROOT}"
  menu_hr
  menu_print_breadcrumb
  echo "${THEME_BOLD}${title}${THEME_RESET}"
  if [[ -n "${subtitle}" ]]; then
    theme_meta_line "${subtitle}"
  fi
}

dev_menu_init() {
  local fedora_root="${1:-${_FEDORA_ROOT}}"
  menu_init "Development lane" "${fedora_root}" 0
  menu_set_header_fn dev_menu_header
}

# ---------- Workstation ----------
_dev_workstation_items() {
  theme_section "Git"
  menu_item 1 "Git setup" "prompts for name/email"
  menu_item 2 "Git config status" "read-only"
  theme_section "Desktop"
  menu_item 3 "Install VS Code" "sudo"
  menu_item 4 "Desktop: Cinnamon + fallbacks" "sudo · @cinnamon-desktop"
  menu_item 5 "Desktop: Cinnamon only" "sudo"
  menu_item 6 "Desktop status" "installed sessions"
  menu_item 7 "Set Cinnamon default" "sudo"
  menu_item_back
}

_dev_workstation_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script dev/git_setup.sh; menu_pause; return 0 ;;
    2) menu_run_script_scroll dev/git_setup.sh --status; menu_pause; return 0 ;;
    3) menu_run_sudo_script dev/install_vscode.sh; menu_pause; return 0 ;;
    4) menu_run_sudo_script dev/desktop_setup.sh; menu_pause; return 0 ;;
    5) menu_run_sudo_script dev/desktop_setup.sh --cinnamon-only; menu_pause; return 0 ;;
    6) menu_run_script dev/desktop_setup.sh --status; menu_pause; return 0 ;;
    7) menu_run_sudo_script dev/desktop_setup.sh --set-default; menu_pause; return 0 ;;
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

dev_menu_help() {
  menu_help_docs_loop "dev/README.md" "guides · dev lane"
}

# ---------- Main dev menu ----------
_dev_main_items() {
  theme_section "Areas"
  menu_item 1 "Workstation" "git · vscode · desktop"
  menu_item 2 "Infrastructure" "podman · docker · kvm"
  menu_item 3 "Web stack" "apache · mariadb · phpmyadmin"
  menu_item 4 "Help & docs" "guides · getting started"
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
  menu_loop "Development menu" "daily dev tools · not part of guided rebuild core" \
    _dev_main_items _dev_main_dispatch
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
