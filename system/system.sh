#!/usr/bin/env bash
# system.sh — System lane launcher (host, maintenance, logs)
# Version: 0.1.0
#
# Run:
#   ./system/system.sh
#   ./system/system.sh update
#   ./system/system.sh logs
#   ./system/system.sh --help

set -euo pipefail

SYSTEM_LAUNCHER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${SYSTEM_LAUNCHER_DIR}/.." && pwd)"

# shellcheck source=lib/menu.sh
source "${SYSTEM_LAUNCHER_DIR}/lib/menu.sh"

usage() {
  cat <<EOF
System lane — host snapshots, updates, backups, logs, research doctor.

Usage: $(basename "$0") [command|option]

Options:
  --help, -h     Show this help
  --menu         Interactive menu (default)

Commands:
  update         Full Fedora update (sudo)
  info           Host snapshot
  monitor        Live dashboard
  backup         Export system state
  doctor         Full research doctor (Android + MobSF)
  logs           Open logs submenu (or use: log_engine.sh)

Toolkit root: ${FEDORA_ROOT}
EOF
}

if [[ $# -eq 0 ]]; then
  system_menu_init "${FEDORA_ROOT}"
  system_main_menu
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --menu)
      system_menu_init "${FEDORA_ROOT}"
      system_main_menu
      exit 0
      ;;
    update) exec sudo bash "${SYSTEM_LAUNCHER_DIR}/system_update.sh" ;;
    info) exec bash "${SYSTEM_LAUNCHER_DIR}/system_info.sh" ;;
    monitor) exec bash "${SYSTEM_LAUNCHER_DIR}/system_monitor.sh" ;;
    backup) exec bash "${SYSTEM_LAUNCHER_DIR}/backup_state.sh" ;;
    doctor) exec bash "${SYSTEM_LAUNCHER_DIR}/research_doctor.sh" ;;
    logs)
      system_menu_init "${FEDORA_ROOT}"
      system_menu_logs
      exit 0
      ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
done
