#!/usr/bin/env bash
# install_vscode.sh — Install Visual Studio Code from Microsoft repo
# Version: 0.3.1
#
# Run:
#   sudo ./dev/install_vscode.sh
#   sudo ./dev/install_vscode.sh --help

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/packages.sh
source "${_SCRIPT_DIR}/../lib/packages.sh"

VSCODE_REPO="/etc/yum.repos.d/vscode.repo"
VSCODE_PKG=code
SKIP_CHECK_UPDATE=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Install Visual Studio Code from packages.microsoft.com (gpgcheck=1).
Idempotent: exits 0 if code is already installed.

Options:
  --help, -h              Show this help
  --skip-check-update     Skip 'dnf check-update' before install

Run with sudo.
EOF
}

vscode_report_installed() {
  local path ver
  path="$(pkg_binary_path "${VSCODE_PKG}" 2>/dev/null || echo /usr/bin/${VSCODE_PKG})"
  ver="$("${path}" --version 2>/dev/null | head -n 1 || rpm -q "${VSCODE_PKG}" 2>/dev/null || echo unknown)"
  ok "Visual Studio Code already installed: ${path} (${ver})"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --skip-check-update) SKIP_CHECK_UPDATE=1; shift ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
done

require_root "Run with sudo: sudo ./dev/install_vscode.sh"

if pkg_present "${VSCODE_PKG}"; then
  vscode_report_installed
  exit 0
fi

info "Importing Microsoft GPG key..."
rpm --import https://packages.microsoft.com/keys/microsoft.asc

info "Adding Visual Studio Code repository..."
if [[ -f "${VSCODE_REPO}" ]]; then
  cp -a "${VSCODE_REPO}" "${VSCODE_REPO}.bak.$(date +%Y%m%d%H%M%S)"
  ok "Backed up existing ${VSCODE_REPO}"
fi

cat > "${VSCODE_REPO}" <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

if (( SKIP_CHECK_UPDATE == 0 )); then
  info "Refreshing package metadata..."
  check_rc=0
  dnf -q check-update >/dev/null 2>&1 || check_rc=$?
  case "${check_rc}" in
    0|100) ok "Package metadata refreshed" ;;
    *) warn "Package update check failed (exit ${check_rc}); install will still resolve metadata" ;;
  esac
fi

pkg_install_if_missing "${VSCODE_PKG}"

if pkg_present "${VSCODE_PKG}"; then
  path="$(pkg_binary_path "${VSCODE_PKG}" 2>/dev/null || echo /usr/bin/${VSCODE_PKG})"
  ok "Visual Studio Code installation complete: ${path}"
  exit 0
fi

die "Visual Studio Code installation failed"
