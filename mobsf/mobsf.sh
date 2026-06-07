#!/usr/bin/env bash
# mobsf.sh — MobSF lane launcher (standalone menu + CLI shortcuts)
# Version: 0.1.0
#
# Run:
#   ./mobsf/mobsf.sh              Interactive MobSF menu
#   ./mobsf/mobsf.sh --doctor     Readiness check
#   ./mobsf/mobsf.sh install      Bootstrap stack (sudo -E)
#   ./mobsf/mobsf.sh start|stop   Stack control
#   ./mobsf/mobsf.sh --help

set -euo pipefail

MOBSF_LAUNCHER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${MOBSF_LAUNCHER_DIR}/.." && pwd)"

# shellcheck source=lib/menu.sh
source "${MOBSF_LAUNCHER_DIR}/lib/menu.sh"

mobsf_usage() {
  cat <<EOF
MobSF lane launcher — Podman stack for static APK analysis.

Usage: $(basename "$0") [command|option]

Options:
  --help, -h     Show this help
  --menu         Interactive menu (default)
  --doctor       Run mobsf_doctor.sh

Commands:
  install        Bootstrap stack (sudo -E)
  start          Start stack (sudo -E if needed for SELinux)
  stop           Stop stack
  status         Show container status
  logs           Tail mobsf service logs
  update         Pull images + migrate (sudo -E)
  cleanup        Remove orphan MobSF containers

Web UI: http://127.0.0.1:8080/  ·  login: mobsf / mobsf

Toolkit root: ${FEDORA_ROOT}
EOF
}

mobsf_exec_cli() {
  local cmd="$1"
  shift
  local script=""
  local use_sudo_env=0

  case "${cmd}" in
    install) script="mobsf_install.sh"; use_sudo_env=1 ;;
    start) script="mobsf_start.sh"; use_sudo_env=1 ;;
    stop) script="mobsf_stop.sh" ;;
    status) script="mobsf_status.sh" ;;
    logs) script="mobsf_logs.sh" ;;
    update) script="mobsf_update.sh"; use_sudo_env=1 ;;
    cleanup) script="mobsf_cleanup.sh" ;;
    *)
      die "Unknown command: ${cmd} (try --help)"
      ;;
  esac

  if (( use_sudo_env )); then
    exec sudo -E bash "${MOBSF_LAUNCHER_DIR}/${script}" "$@"
  fi
  exec bash "${MOBSF_LAUNCHER_DIR}/${script}" "$@"
}

if [[ $# -eq 0 ]]; then
  mobsf_menu_init "${FEDORA_ROOT}"
  mobsf_main_menu
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      mobsf_usage
      exit 0
      ;;
    --menu)
      mobsf_menu_init "${FEDORA_ROOT}"
      mobsf_main_menu
      exit 0
      ;;
    --doctor)
      exec bash "${MOBSF_LAUNCHER_DIR}/mobsf_doctor.sh"
      ;;
    install|start|stop|status|logs|update|cleanup)
      mobsf_exec_cli "$@"
      ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
done
