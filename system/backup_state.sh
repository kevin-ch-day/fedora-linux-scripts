#!/usr/bin/env bash
# backup_state.sh — Export system state before reinstall or major changes
# Version: 0.1.1
#
# Run:
#   ./backup_state.sh
#   ./backup_state.sh --output ~/backups/fedora-state-2026

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${_SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/health.sh
source "${_SCRIPT_DIR}/../lib/health.sh"
# shellcheck source=../lib/logging.sh
source "${_SCRIPT_DIR}/../lib/logging.sh"

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output|-o)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --help|-h)
      cat <<EOF
Usage: $(basename "$0") [--output DIR]

Export RPM list, flatpak apps, pip user packages, git config, and system info.

Run as your normal user (not plain root). sudo is not required.
Default output: logs/backups/backup-YYYYMMDD-HHMMSS/
EOF
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

require_invoker_user "Run as your normal user: ./system/backup_state.sh"

if [[ -z "${OUT_DIR}" ]]; then
  OUT_DIR="$(log_backup_dir)/backup-${STAMP}"
fi

ensure_dir "${OUT_DIR}"
info "Writing backup to: ${OUT_DIR}"

{
  echo "Fedora state backup"
  echo "Created: $(date -Is)"
  echo "Host: $(hostname)"
  echo "User: $(real_user)"
  echo
} | tee "${OUT_DIR}/README.txt"

health_hostname > "${OUT_DIR}/hostname.txt" 2>/dev/null || true
health_os_pretty > "${OUT_DIR}/os.txt" 2>/dev/null || true
health_kernel > "${OUT_DIR}/kernel.txt" 2>/dev/null || true
cp /etc/fedora-release "${OUT_DIR}/fedora-release.txt" 2>/dev/null || true

if have rpm; then
  info "Exporting RPM package list..."
  rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > "${OUT_DIR}/rpm-packages.txt"
fi

if have dnf; then
  dnf repolist --all > "${OUT_DIR}/dnf-repolist.txt" 2>/dev/null || true
  dnf history list > "${OUT_DIR}/dnf-history.txt" 2>/dev/null || true
fi

if have flatpak; then
  flatpak list --app --columns=application,version,branch > "${OUT_DIR}/flatpak-apps.txt" 2>/dev/null || true
fi

if have python3; then
  run_as_real_user python3 -m pip list --user > "${OUT_DIR}/pip-user.txt" 2>/dev/null || true
fi

USER_HOME="$(real_home)"

if have git; then
  run_as_real_user git config --global --list > "${OUT_DIR}/git-global.config" 2>/dev/null || true
fi

if [[ -d "${USER_HOME}/.local/bin" ]]; then
  ls -la "${USER_HOME}/.local/bin" > "${OUT_DIR}/user-local-bin.txt" 2>/dev/null || true
fi

if [[ -d "${USER_HOME}/Android/Sdk" ]]; then
  ls -la "${USER_HOME}/Android/Sdk" > "${OUT_DIR}/android-sdk-dir.txt" 2>/dev/null || true
fi

info "Running system info snapshot..."
bash "${_SCRIPT_DIR}/system_info.sh" > "${OUT_DIR}/system_info.txt" 2>&1 || true

ok "Backup complete: ${OUT_DIR}"
echo "[NEXT] Copy ${OUT_DIR} to external storage before reinstall."
