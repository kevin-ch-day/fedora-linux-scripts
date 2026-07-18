#!/usr/bin/env bash
# dev/lib/menu.sh — Developer workstation area menus (uses lib/menu.sh theme)
# Version: 0.3.3
#
# Standalone:  ./dev/dev.sh
# From main:   ./run.sh → [4] Developer tools or ./run.sh --dev
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

dev_menu_desktop_header() {
  local title="$1"
  local subtitle="${2:-}"
  menu_clear_screen
  theme_lane_banner "Desktop environments" desktop \
    "install and manage Fedora graphical login sessions"
  theme_meta_line "PATH / $(menu_path_text)"
  menu_hr
  theme_page_title "${title}"
  if [[ -n "${subtitle}" ]]; then
    theme_meta_line "${subtitle}"
  fi
}

dev_menu_developer_header() {
  local title="$1"
  local subtitle="${2:-}"
  menu_clear_screen
  theme_lane_banner "Developer tools" dev \
    "configure and verify local developer tooling"
  theme_meta_line "PATH / $(menu_path_text)"
  menu_hr
  theme_page_title "${title}"
  if [[ -n "${subtitle}" ]]; then
    theme_meta_line "${subtitle}"
  fi
}

dev_menu_virtualization_header() {
  local title="$1"
  local subtitle="${2:-}"
  menu_clear_screen
  theme_lane_banner "Virtualization & containers" virt \
    "containers and VM host support"
  theme_meta_line "PATH / $(menu_path_text)"
  menu_hr
  theme_page_title "${title}"
  if [[ -n "${subtitle}" ]]; then
    theme_meta_line "${subtitle}"
  fi
}

dev_menu_web_header() {
  local title="$1"
  local subtitle="${2:-}"
  menu_clear_screen
  theme_lane_banner "Web/database stack" web \
    "install and verify local web and database services"
  theme_meta_line "PATH / $(menu_path_text)"
  menu_hr
  theme_page_title "${title}"
  if [[ -n "${subtitle}" ]]; then
    theme_meta_line "${subtitle}"
  fi
}

dev_menu_init() {
  local fedora_root="${1:-${_FEDORA_ROOT}}"
  menu_init "Developer tools" "${fedora_root}" 0
  theme_set_lane dev
  menu_set_header_fn dev_menu_developer_header
}

# ---------- Developer tools ----------
_dev_developer_tools_items() {
  theme_section "Git"
  menu_item 1 "Git setup" "prompts for name/email"
  menu_item 2 "Git config status" "read-only"
  theme_section "Developer tools"
  menu_item 3 "Install VS Code" "sudo"
  menu_item 4 "Verify developer tools" "git · code"
  menu_item_back
}

_dev_developer_tools_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script dev/git_setup.sh; menu_pause; return 0 ;;
    2) menu_run_script_scroll dev/git_setup.sh --status; menu_pause; return 0 ;;
    3) menu_run_sudo_script_scroll dev/install_vscode.sh; menu_pause; return 0 ;;
    4)
      cmd_available git && ok "git on PATH: $(cmd_binary_path git)" || warn "git not on PATH"
      cmd_available code && ok "code on PATH: $(cmd_binary_path code)" || warn "code not on PATH"
      menu_pause
      return 0
      ;;
    *) return 2 ;;
  esac
}

dev_menu_developer_tools() {
  local prev_header="${MENU_HEADER_FN}"
  menu_set_header_fn dev_menu_developer_header
  menu_loop "Developer tools" "git · vscode · shell helpers" \
    _dev_developer_tools_items _dev_developer_tools_dispatch
  menu_set_header_fn "${prev_header}"
}

# ---------- Desktop environments ----------
_dev_desktop_items() {
  theme_section "Install"
  menu_item 1 "Install Cinnamon baseline" "Cinnamon primary · GNOME/XFCE recovery sessions"
  menu_item 2 "Install KDE Plasma" "optional desktop session"
  menu_item 3 "Install MATE" "optional desktop session"
  menu_item 4 "Install LXQt" "optional desktop session"
  menu_item 5 "Install all desktop environments" "Cinnamon baseline · KDE · MATE · LXQt"
  theme_section "Status and defaults"
  menu_item 6 "Show installed login sessions" "read-only"
  menu_item 7 "Set Cinnamon as login default" "AccountsService · ~/.dmrc"
  menu_item_back
}

_dev_desktop_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_sudo_script_scroll dev/desktop_setup.sh; menu_pause; return 0 ;;
    2) menu_run_sudo_script_scroll dev/desktop_setup.sh --only-profiles kde --default-session plasma; menu_pause; return 0 ;;
    3) menu_run_sudo_script_scroll dev/desktop_setup.sh --only-profiles mate --default-session mate; menu_pause; return 0 ;;
    4) menu_run_sudo_script_scroll dev/desktop_setup.sh --only-profiles lxqt --default-session lxqt; menu_pause; return 0 ;;
    5) menu_run_sudo_script_scroll dev/desktop_setup.sh --profiles kde,mate,lxqt; menu_pause; return 0 ;;
    6) menu_run_script dev/desktop_setup.sh --status; menu_pause; return 0 ;;
    7) menu_run_sudo_script_scroll dev/desktop_setup.sh --set-default; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

dev_menu_desktop_environments() {
  local prev_header="${MENU_HEADER_FN}"
  menu_set_header_fn dev_menu_desktop_header
  menu_loop "Desktop environments" "Cinnamon primary · GNOME/XFCE recovery · KDE · MATE · LXQt" \
    _dev_desktop_items _dev_desktop_dispatch
  menu_set_header_fn "${prev_header}"
}

# ---------- Virtualization ----------
_dev_infra_items() {
  theme_section "Containers"
  menu_item 1 "Install Podman engine" "podman package · basic verify"
  menu_item 2 "Install Docker engine" "docker repo · engine package"
  theme_section "Virtual machines"
  menu_item 3 "Install KVM/libvirt" "qemu · libvirt · virt-manager"
  menu_item 4 "Install VirtualBox host" "RPM Fusion · kernel modules · vboxusers"
  theme_section "Checks"
  menu_item 5 "Check virtualization status" "podman · docker · libvirtd · vboxdrv"
  menu_item_back
}

_dev_infra_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_sudo_script_scroll dev/fedora_container_kvm_setup.sh --podman-only; menu_pause; return 0 ;;
    2) menu_run_sudo_script_scroll dev/fedora_container_kvm_setup.sh --docker-only; menu_pause; return 0 ;;
    3) menu_run_sudo_script_scroll dev/fedora_container_kvm_setup.sh --kvm-only; menu_pause; return 0 ;;
    4) menu_run_sudo_script_scroll dev/virtualbox_setup.sh; menu_pause; return 0 ;;
    5) services_status_virtualization_stack; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

dev_menu_infrastructure() {
  local prev_header="${MENU_HEADER_FN}"
  menu_set_header_fn dev_menu_virtualization_header
  menu_loop "Virtualization & containers" "podman · docker · kvm/libvirt · virtualbox" \
    _dev_infra_items _dev_infra_dispatch
  menu_set_header_fn "${prev_header}"
}

# ---------- Web/database stack ----------
_dev_web_items() {
  theme_section "Components"
  menu_item 1 "Apache" "install/enable httpd only"
  menu_item 2 "MariaDB packages only" "migration-safe · no service start or explicit init"
  menu_item_danger 3 "Enable/start MariaDB" "changes database service state"
  menu_item 4 "PHP" "install php + extensions only"
  menu_item 5 "phpMyAdmin" "localhost default · restarts Apache"
  theme_section "Checks"
  menu_item 6 "Check web/database status" "Apache · MariaDB · PHP · phpMyAdmin"
  menu_item 7 "Remove public info.php" "if created during PHP testing"
  menu_item_back
}

_dev_web_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_sudo_script_scroll dev/lamp_python_setup.sh --apache-only; menu_pause; return 0 ;;
    2) menu_run_sudo_script_scroll dev/lamp_python_setup.sh --mariadb-only --no-start; menu_pause; return 0 ;;
    3)
      warn "This enables and starts MariaDB. Do not continue until the database migration plan is finalized."
      if confirm "Enable and start MariaDB now?"; then
        menu_run_sudo_script_scroll dev/lamp_python_setup.sh --mariadb-only
      else
        info "MariaDB service activation cancelled"
      fi
      menu_pause
      return 0
      ;;
    4) menu_run_sudo_script_scroll dev/lamp_python_setup.sh --php-only; menu_pause; return 0 ;;
    5) menu_run_sudo_script_scroll dev/phpmyadmin_setup.sh; menu_pause; return 0 ;;
    6) menu_run_script_scroll dev/web_stack_doctor.sh; menu_pause; return 0 ;;
    7) menu_run_sudo_script_scroll dev/lamp_python_setup.sh --remove-info-php; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

dev_menu_web_stack() {
  local prev_header="${MENU_HEADER_FN}"
  menu_set_header_fn dev_menu_web_header
  menu_loop "Web/database stack" "Apache · MariaDB · PHP · phpMyAdmin" \
    _dev_web_items _dev_web_dispatch
  menu_set_header_fn "${prev_header}"
}

dev_menu_help() {
  menu_help_docs_loop "dev/README.md" "guides · dev lane"
}

_dev_hub_items() {
  theme_section "Workstation areas"
  menu_item_lane 1 dev "Developer tools" "git · vscode · shell helpers"
  menu_item_lane 2 desktop "Desktop environments" "cinnamon · kde · mate · lxqt"
  menu_item_lane 3 virt "Virtualization & containers" "podman · docker · kvm · virtualbox"
  menu_item_lane 4 web "Web/database stack" "apache · mariadb · php · phpmyadmin"
  theme_section "Docs"
  menu_item 5 "Help & docs" "dev/README.md · getting started"
  menu_item_lane_exit
}

_dev_hub_dispatch() {
  case "$1" in
    0) menu_lane_handle_main_exit ;;
    1) dev_menu_developer_tools; return 0 ;;
    2) dev_menu_desktop_environments; return 0 ;;
    3) dev_menu_infrastructure; return 0 ;;
    4) dev_menu_web_stack; return 0 ;;
    5) dev_menu_help; return 0 ;;
    *) return 2 ;;
  esac
}

dev_main_menu() {
  local prev_header="${MENU_HEADER_FN}"
  menu_set_header_fn dev_menu_developer_header
  menu_loop "Developer workstation" "pick an install area" \
    _dev_hub_items _dev_hub_dispatch
  menu_set_header_fn "${prev_header}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
