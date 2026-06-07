#!/usr/bin/env bash
# mobsf_install.sh — Bootstrap MobSF Podman stack on Fedora (first-time install)
# Version: 0.1.0
#
# Run:
#   sudo -E ./mobsf/mobsf_install.sh
#   sudo -E ./mobsf/mobsf_install.sh --help

set -euo pipefail

MOBSF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${MOBSF_DIR}/.." && pwd)"
# shellcheck source=../lib/packages.sh
source "${FEDORA_ROOT}/lib/packages.sh"
# shellcheck source=lib/mobsf.sh
source "${MOBSF_DIR}/lib/mobsf.sh"
# shellcheck source=../lib/logging.sh
source "${FEDORA_ROOT}/lib/logging.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      cat <<EOF
Usage: $(basename "$0")

First-time MobSF install for Fedora (rootless Podman):
  - installs podman + podman-compose if missing
  - deploys Fedora-patched compose to ~/MobSF/compose/
  - creates data dirs with SELinux labels
  - pulls images and starts the stack

UI: http://127.0.0.1:8080/  (login: mobsf / mobsf)

Run with: sudo -E $0
EOF
      exit 0
      ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
done

require_root "Run with: sudo -E ./mobsf/mobsf_install.sh"
errors_init_script "mobsf_install.sh"
init_script_logging "${FEDORA_LOG_MOBSF}" "mobsf_install.sh" "MobSF install"

info "Installing prerequisites..."
pkg_install_cmd_if_missing podman podman
pkg_install_cmd_if_missing podman-compose podman-compose
pkg_install_cmd_if_missing curl curl

mobsf_stack_install

echo "[NEXT] ./mobsf/mobsf_doctor.sh"
echo "[NEXT] Upload APK at ${MOBSF_UI_URL}"
