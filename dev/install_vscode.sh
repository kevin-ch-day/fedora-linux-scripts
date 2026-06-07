#!/usr/bin/env bash
# install_vscode.sh — Install Visual Studio Code from Microsoft repo
# Version: 0.3.0
#
# Run:
#   sudo ./dev/install_vscode.sh
#   sudo ./dev/install_vscode.sh --help

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/packages.sh
source "${_SCRIPT_DIR}/../lib/packages.sh"

VSCODE_REPO="/etc/yum.repos.d/vscode.repo"
SKIP_CHECK_UPDATE=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Install Visual Studio Code from packages.microsoft.com (gpgcheck=1).

Options:
  --help, -h              Show this help
  --skip-check-update     Skip 'dnf check-update' before install

Run with sudo.
EOF
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
  dnf check-update -y || warn "dnf check-update returned non-zero (continuing)"
fi

pkg_install_if_missing code

if have code; then
  ok "Visual Studio Code installation complete: $(command -v code)"
else
  die "Visual Studio Code installation failed"
fi
