#!/usr/bin/env bash
# lamp_python_setup.sh — Fedora setup for LAMP stack + Python MySQL connectors
# Version: 0.3.0
#
# Run:
#   sudo ./dev/lamp_python_setup.sh
#   sudo ./dev/lamp_python_setup.sh --with-info-php   # optional phpinfo (remove after test)
#   sudo ./dev/lamp_python_setup.sh --remove-info-php

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/packages.sh
source "${_SCRIPT_DIR}/../lib/packages.sh"
# shellcheck source=../lib/services.sh
source "${_SCRIPT_DIR}/../lib/services.sh"

UPGRADE=0
WITH_INFO_PHP=0
REMOVE_INFO_PHP=0
INFO_PHP="/var/www/html/info.php"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Install Apache (httpd), MariaDB, PHP (+ mysqlnd), and user-scoped Python DB
connectors for $(real_user).

Options:
  --help, -h          Show this help
  --upgrade           Run 'dnf upgrade --refresh' before install (off by default)
  --with-info-php     Create /var/www/html/info.php for PHP smoke test
                      (security risk — remove after verifying PHP works)
  --remove-info-php   Delete info.php if present

Run with sudo.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --upgrade) UPGRADE=1; shift ;;
    --with-info-php) WITH_INFO_PHP=1; shift ;;
    --remove-info-php) REMOVE_INFO_PHP=1; shift ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
done

require_root "Run with sudo: sudo ./dev/lamp_python_setup.sh"

if (( REMOVE_INFO_PHP )); then
  if [[ -f "${INFO_PHP}" ]]; then
    rm -f "${INFO_PHP}"
    ok "Removed ${INFO_PHP}"
  else
    ok "No info.php to remove"
  fi
  if (( WITH_INFO_PHP == 0 && UPGRADE == 0 )); then
    exit 0
  fi
fi

if (( UPGRADE )); then
  dnf_upgrade_refresh
fi

info "Installing Apache (httpd)..."
pkg_install_if_missing httpd
service_enable_now httpd
ok "Apache installed and running on http://127.0.0.1/"

info "Installing MySQL (MariaDB)..."
pkg_install_if_missing mariadb-server
pkg_install_if_missing mariadb
service_enable_now mariadb
ok "MySQL/MariaDB installed and running"
echo "[NEXT] Run 'sudo mysql_secure_installation' to configure root password."

info "Installing PHP and extensions..."
for pkg in php php-mysqlnd php-cli php-json php-common php-fpm php-gd php-curl php-xml php-mbstring; do
  pkg_install_if_missing "${pkg}"
done
service_restart httpd
ok "PHP installed with MySQL support"

if [[ ! -f /var/www/html/index.html ]]; then
  cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html><head><title>LAMP</title></head>
<body><h1>LAMP stack OK</h1><p>Fedora rebuild kit — dev/lamp_python_setup.sh</p></body></html>
EOF
  ok "Default index.html created at http://127.0.0.1/"
fi

if (( WITH_INFO_PHP )); then
  echo "<?php phpinfo(); ?>" > "${INFO_PHP}"
  chmod 644 "${INFO_PHP}"
  ok "Test file created at http://127.0.0.1/info.php"
  warn "Remove after testing: sudo ./dev/lamp_python_setup.sh --remove-info-php"
else
  info "Skipping info.php (use --with-info-php only for a one-time PHP smoke test)"
fi

info "Installing Python and MySQL connectors..."
pkg_install_if_missing python3
pkg_install_if_missing python3-pip
run_as_real_user python3 -m pip install --upgrade --user pip
run_as_real_user python3 -m pip install --user mysql-connector-python
run_as_real_user python3 -m pip install --user SQLAlchemy PyMySQL
ok "Python MySQL connectors installed (mysql.connector, SQLAlchemy, PyMySQL)"

echo "[SETUP] Doctor summary:"
if pkg_binary_path python3 >/dev/null 2>&1; then ok "python3"; else warn "python3 missing"; fi
if pkg_binary_path pip3 >/dev/null 2>&1 || pkg_binary_path pip >/dev/null 2>&1; then ok "pip"; else warn "pip missing"; fi
run_as_real_user python3 -c "import mysql.connector" 2>/dev/null && ok "mysql.connector (Python)" || warn "mysql.connector missing"
if pkg_binary_path mysql >/dev/null 2>&1; then ok "mysql (cli)"; else warn "mysql missing"; fi
if pkg_binary_path php >/dev/null 2>&1; then ok "php"; else warn "php missing"; fi
if pkg_binary_path httpd >/dev/null 2>&1 || pkg_present httpd apache; then ok "apache httpd"; else warn "httpd missing"; fi

ok "LAMP + Python-MySQL setup complete!"
echo
echo "[NEXT] Visit http://127.0.0.1/ to confirm Apache."
echo "[NEXT] Use 'mysql -u root -p' to connect to MariaDB."
echo "[NEXT] ./dev/web_stack_doctor.sh"
