#!/usr/bin/env bash
# mobsf_autostart.sh — Install/remove MobSF user systemd unit
# Version: 0.1.0
#
# Run:
#   ./mobsf/mobsf_autostart.sh install
#   sudo ./mobsf/mobsf_autostart.sh install --linger   # start at boot (no login)
#   ./mobsf/mobsf_autostart.sh status
#   ./mobsf/mobsf_autostart.sh remove

set -euo pipefail

MOBSF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mobsf.sh
source "${MOBSF_DIR}/lib/mobsf.sh"

ENABLE_LINGER=0

usage() {
  cat <<EOF
Usage: $(basename "$0") <install|remove|status> [options]

Manage MobSF user systemd unit (login autostart via podman-compose).

Commands:
  install        Write and enable ~/.config/systemd/user/mobsf-stack.service
  remove         Disable and delete the user unit
  status         Show unit + linger state

Options:
  --linger       With install: enable loginctl linger (boot autostart; needs sudo)
  --help, -h     Show this help

After install:
  systemctl --user start mobsf-stack.service
  systemctl --user status mobsf-stack.service
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --linger) ENABLE_LINGER=1; shift ;;
    install|remove|status) break ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

[[ $# -ge 1 ]] || { usage >&2; exit 2; }

cmd="$1"
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --linger) ENABLE_LINGER=1; shift ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

case "${cmd}" in
  install) mobsf_systemd_install "${ENABLE_LINGER}" ;;
  remove) mobsf_systemd_remove ;;
  status) mobsf_systemd_status ;;
  *) die "Unknown command: ${cmd} (try --help)" ;;
esac
