#!/usr/bin/env bash
# phpmyadmin_setup.sh — Fedora setup for phpMyAdmin (localhost by default)
# Version: 0.3.1
#
# Run:
#   sudo ./dev/phpmyadmin_setup.sh
#   sudo ./dev/phpmyadmin_setup.sh --allow-remote   # insecure — LAN-wide access

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/packages.sh
source "${_SCRIPT_DIR}/../lib/packages.sh"
# shellcheck source=../lib/services.sh
source "${_SCRIPT_DIR}/../lib/services.sh"

UPGRADE=0
ALLOW_REMOTE=0
PHPMYADMIN_CONF="/etc/httpd/conf.d/phpMyAdmin.conf"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Install phpMyAdmin and required PHP extensions.

By default Apache keeps phpMyAdmin at Require local (127.0.0.1 only).

Options:
  --help, -h          Show this help
  --upgrade           Run 'dnf upgrade --refresh' before install
  --allow-remote      Change Require local → Require all granted
                      (exposes phpMyAdmin on all interfaces — lab use only)

Run with sudo.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --upgrade) UPGRADE=1; shift ;;
    --allow-remote) ALLOW_REMOTE=1; shift ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
done

require_root "Run with sudo: sudo ./dev/phpmyadmin_setup.sh"

if (( UPGRADE )); then
  dnf_upgrade_refresh
fi

info "Installing phpMyAdmin and required packages..."
pkg_install_rpm_if_missing phpMyAdmin
for pkg in php-mbstring php-zip php-gd php-curl php-xml; do
  pkg_install_rpm_if_missing "${pkg}"
done

info "Configuring Apache for phpMyAdmin..."
if [[ ! -f "${PHPMYADMIN_CONF}" ]]; then
  warn "phpMyAdmin config not found — check /etc/httpd/conf.d/"
elif (( ALLOW_REMOTE )); then
  warn "Enabling remote access to phpMyAdmin (Require all granted)"
  if ! confirm "Allow phpMyAdmin from any client?"; then
    die "Aborted — use default localhost-only install without --allow-remote"
  fi
  cp -a "${PHPMYADMIN_CONF}" "${PHPMYADMIN_CONF}.bak.$(date +%Y%m%d%H%M%S)"
  sed -i 's/Require local/Require all granted/' "${PHPMYADMIN_CONF}"
  ok "Apache config updated for remote access (backup saved)"
else
  if grep -q 'Require all granted' "${PHPMYADMIN_CONF}" 2>/dev/null; then
    info "Restoring localhost-only access (Require local)"
    cp -a "${PHPMYADMIN_CONF}" "${PHPMYADMIN_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    sed -i 's/Require all granted/Require local/' "${PHPMYADMIN_CONF}"
    ok "Apache config reverted to localhost-only (backup saved)"
  else
    ok "Keeping localhost-only access (Require local)"
  fi
fi

info "Restarting Apache..."
service_restart httpd
ok "Apache restarted"

if command -v getenforce >/dev/null && [[ "$(getenforce)" == "Enforcing" ]]; then
  info "Adjusting SELinux for phpMyAdmin..."
  setsebool -P httpd_can_network_connect_db 1
  ok "SELinux updated for phpMyAdmin"
fi

theme_result_ready "phpMyAdmin installation complete"
theme_note "Open: http://127.0.0.1/phpmyadmin"
if (( ALLOW_REMOTE )); then
  warn "Remote access enabled — restrict with firewall or revert config backup"
fi
theme_note "Detailed status: ./dev/web_stack_doctor.sh"
