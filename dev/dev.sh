#!/usr/bin/env bash
# dev.sh — Developer workstation area launcher
# Version: 0.1.4
#
# Run:
#   ./dev/dev.sh
#   ./fedora.sh --dev
#   ./dev/dev.sh web-doctor
#   ./dev/dev.sh git --status
#   ./dev/dev.sh --help

set -euo pipefail

DEV_LAUNCHER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${DEV_LAUNCHER_DIR}/.." && pwd)"

# shellcheck source=lib/menu.sh
source "${DEV_LAUNCHER_DIR}/lib/menu.sh"

usage() {
  cat <<EOF
Developer workstation areas — developer tools, desktop environments, virtualization, and web/database services.

From main entry: ./fedora.sh → [2]  or  ./fedora.sh --dev

Usage: $(basename "$0") [command|option]

Options:
  --help, -h     Show this help
  --menu         Interactive Developer tools menu (default)
  --developer-tools      Open Developer tools menu
  --desktop-environments Open Desktop environments menu
  --virtualization       Open Virtualization & containers menu
  --web-stack            Open Web/database stack menu

Commands:
  git [opts]     Configure git (see ./dev/git_setup.sh --help)
  vscode         Install VS Code (sudo)
  desktop        Install Cinnamon baseline + GNOME/XFCE recovery (sudo)
  desktop-kde    KDE Plasma desktop (sudo)
  desktop-mate   MATE desktop (sudo)
  desktop-lxqt   LXQt desktop (sudo)
  desktop-budgie Budgie desktop (sudo)
  desktop-cosmic COSMIC desktop (sudo)
  desktop-sway   Sway compositor stack (sudo)
  desktop-cinnamon  Cinnamon only (sudo)
  desktop-default   Set Cinnamon default session (sudo)
  desktop-status List installed login sessions
  kvm            Containers + KVM setup (sudo)
  virtualbox     VirtualBox host setup via RPM Fusion Free (sudo)
  lamp           LAMP + Python connectors (sudo)
  phpmyadmin     Install phpMyAdmin (sudo)
  web-doctor     Check Apache/MariaDB/PHP/phpMyAdmin

Examples:
  ./dev/dev.sh git --status
  ./dev/dev.sh git --help

Toolkit root: ${FEDORA_ROOT}
EOF
}

if [[ $# -eq 0 ]]; then
  dev_menu_init "${FEDORA_ROOT}"
  dev_menu_developer_tools
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --menu)
      dev_menu_init "${FEDORA_ROOT}"
      dev_menu_developer_tools
      exit 0
      ;;
    --developer-tools)
      shift
      dev_menu_init "${FEDORA_ROOT}"
      dev_menu_developer_tools
      exit 0
      ;;
    --desktop-environments)
      shift
      dev_menu_init "${FEDORA_ROOT}"
      dev_menu_desktop_environments
      exit 0
      ;;
    --virtualization)
      shift
      dev_menu_init "${FEDORA_ROOT}"
      dev_menu_infrastructure
      exit 0
      ;;
    --web-stack)
      shift
      dev_menu_init "${FEDORA_ROOT}"
      dev_menu_web_stack
      exit 0
      ;;
    git) shift; exec bash "${DEV_LAUNCHER_DIR}/git_setup.sh" "$@" ;;
    vscode) shift; exec sudo bash "${DEV_LAUNCHER_DIR}/install_vscode.sh" "$@" ;;
    desktop) shift; exec sudo bash "${DEV_LAUNCHER_DIR}/desktop_setup.sh" "$@" ;;
    desktop-kde) shift; exec sudo bash "${DEV_LAUNCHER_DIR}/desktop_setup.sh" --only-profiles kde --default-session plasma "$@" ;;
    desktop-mate) shift; exec sudo bash "${DEV_LAUNCHER_DIR}/desktop_setup.sh" --only-profiles mate --default-session mate "$@" ;;
    desktop-lxqt) shift; exec sudo bash "${DEV_LAUNCHER_DIR}/desktop_setup.sh" --only-profiles lxqt --default-session lxqt "$@" ;;
    desktop-budgie) shift; exec sudo bash "${DEV_LAUNCHER_DIR}/desktop_setup.sh" --only-profiles budgie --default-session budgie-desktop "$@" ;;
    desktop-cosmic) shift; exec sudo bash "${DEV_LAUNCHER_DIR}/desktop_setup.sh" --only-profiles cosmic --default-session cosmic "$@" ;;
    desktop-sway) shift; exec sudo bash "${DEV_LAUNCHER_DIR}/desktop_setup.sh" --only-profiles sway --default-session sway "$@" ;;
    desktop-cinnamon) shift; exec sudo bash "${DEV_LAUNCHER_DIR}/desktop_setup.sh" --cinnamon-only "$@" ;;
    desktop-default) shift; exec sudo bash "${DEV_LAUNCHER_DIR}/desktop_setup.sh" --set-default "$@" ;;
    desktop-status) shift; exec bash "${DEV_LAUNCHER_DIR}/desktop_setup.sh" --status "$@" ;;
    kvm) shift; exec sudo bash "${DEV_LAUNCHER_DIR}/fedora_container_kvm_setup.sh" "$@" ;;
    virtualbox) shift; exec sudo bash "${DEV_LAUNCHER_DIR}/virtualbox_setup.sh" "$@" ;;
    lamp) shift; exec sudo bash "${DEV_LAUNCHER_DIR}/lamp_python_setup.sh" "$@" ;;
    phpmyadmin) shift; exec sudo bash "${DEV_LAUNCHER_DIR}/phpmyadmin_setup.sh" "$@" ;;
    web-doctor) shift; exec bash "${DEV_LAUNCHER_DIR}/web_stack_doctor.sh" "$@" ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
done
