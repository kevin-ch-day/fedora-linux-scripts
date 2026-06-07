#!/usr/bin/env bash
# dev.sh — Dev workstation lane launcher
# Version: 0.1.1
#
# Run:
#   ./dev/dev.sh
#   ./dev/dev.sh web-doctor
#   ./dev/dev.sh --help

set -euo pipefail

DEV_LAUNCHER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${DEV_LAUNCHER_DIR}/.." && pwd)"

# shellcheck source=lib/menu.sh
source "${DEV_LAUNCHER_DIR}/lib/menu.sh"

usage() {
  cat <<EOF
Dev workstation lane — git, VS Code, KVM/containers, LAMP, phpMyAdmin.

Usage: $(basename "$0") [command|option]

Options:
  --help, -h     Show this help
  --menu         Interactive menu (default)

Commands:
  git            Configure git for $(real_user)
  vscode         Install VS Code (sudo)
  desktop        Cinnamon + GNOME/XFCE fallbacks (sudo)
  desktop-status List installed login sessions
  kvm            Containers + KVM setup (sudo)
  lamp           LAMP + Python connectors (sudo)
  phpmyadmin     Install phpMyAdmin (sudo)
  web-doctor     Check Apache/MariaDB/PHP/phpMyAdmin

Toolkit root: ${FEDORA_ROOT}
EOF
}

if [[ $# -eq 0 ]]; then
  dev_menu_init "${FEDORA_ROOT}"
  dev_main_menu
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --menu)
      dev_menu_init "${FEDORA_ROOT}"
      dev_main_menu
      exit 0
      ;;
    git) exec bash "${DEV_LAUNCHER_DIR}/git_setup.sh" ;;
    vscode) exec sudo bash "${DEV_LAUNCHER_DIR}/install_vscode.sh" ;;
    desktop) exec sudo bash "${DEV_LAUNCHER_DIR}/desktop_setup.sh" ;;
    desktop-status) exec bash "${DEV_LAUNCHER_DIR}/desktop_setup.sh" --status ;;
    kvm) exec sudo bash "${DEV_LAUNCHER_DIR}/fedora_container_kvm_setup.sh" ;;
    lamp) exec sudo bash "${DEV_LAUNCHER_DIR}/lamp_python_setup.sh" ;;
    phpmyadmin) exec sudo bash "${DEV_LAUNCHER_DIR}/phpmyadmin_setup.sh" ;;
    web-doctor) exec bash "${DEV_LAUNCHER_DIR}/web_stack_doctor.sh" ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
done
