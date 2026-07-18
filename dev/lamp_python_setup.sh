#!/usr/bin/env bash
# lamp_python_setup.sh — Fedora setup for LAMP stack + Python MySQL connectors
# Version: 0.4.0
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
INSTALL_APACHE=1
INSTALL_MARIADB=1
INSTALL_PHP=1
INSTALL_PYTHON_CONNECTORS=1
START_SERVICES=1

run_as_real_user_with_path() {
  local home userbin
  home="$(real_home)"
  userbin="${home}/.local/bin"
  run_as_real_user env "HOME=${home}" "PATH=${userbin}:${PATH}" "$@"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Install Apache (httpd), MariaDB, PHP (+ mysqlnd), and user-scoped Python DB
connectors for $(real_user).

Options:
  --help, -h          Show this help
  --upgrade           Run 'dnf upgrade --refresh' before install (off by default)
  --apache-only       Install/enable Apache only
  --mariadb-only      Install/enable MariaDB only
  --no-start          Install selected packages without enabling, starting, or
                      restarting services (recommended before DB migration)
  --php-only          Install PHP + extensions only (restarts httpd if present)
  --python-only       Install Python MySQL connectors only
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
    --apache-only)
      INSTALL_APACHE=1
      INSTALL_MARIADB=0
      INSTALL_PHP=0
      INSTALL_PYTHON_CONNECTORS=0
      shift
      ;;
    --mariadb-only)
      INSTALL_APACHE=0
      INSTALL_MARIADB=1
      INSTALL_PHP=0
      INSTALL_PYTHON_CONNECTORS=0
      shift
      ;;
    --no-start) START_SERVICES=0; shift ;;
    --php-only)
      INSTALL_APACHE=0
      INSTALL_MARIADB=0
      INSTALL_PHP=1
      INSTALL_PYTHON_CONNECTORS=0
      shift
      ;;
    --python-only)
      INSTALL_APACHE=0
      INSTALL_MARIADB=0
      INSTALL_PHP=0
      INSTALL_PYTHON_CONNECTORS=1
      shift
      ;;
    --with-info-php) WITH_INFO_PHP=1; shift ;;
    --remove-info-php) REMOVE_INFO_PHP=1; shift ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
done

require_root "Run with sudo: sudo ./dev/lamp_python_setup.sh"
common_init_colors
theme_set_lane web

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

if (( INSTALL_APACHE )); then
  info "Installing Apache (httpd)..."
  pkg_install_if_missing httpd
  if (( START_SERVICES )); then
    service_enable_now httpd
    ok "Apache installed and running on http://127.0.0.1/"
  else
    ok "Apache package installed; service state unchanged"
  fi

  if (( START_SERVICES )) && [[ ! -f /var/www/html/index.html ]]; then
    cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html><head><title>LAMP</title></head>
<body><h1>LAMP stack OK</h1><p>Fedora rebuild kit — dev/lamp_python_setup.sh</p></body></html>
EOF
    ok "Default index.html created at http://127.0.0.1/"
  fi
fi

if (( INSTALL_MARIADB )); then
  info "Installing MySQL (MariaDB)..."
  pkg_install_if_missing mariadb-server
  pkg_install_if_missing mariadb
  if (( START_SERVICES )); then
    service_enable_now mariadb
    ok "MySQL/MariaDB installed and running"
    theme_note "After migration planning: sudo mysql_secure_installation"
  else
    ok "MariaDB packages installed; service state unchanged"
    info "Migration deferred: no service activation or database initialization command was run."
  fi
fi

if (( INSTALL_PHP )); then
  info "Installing PHP and extensions..."
  pkg_install_if_missing php
  for pkg in php-mysqlnd php-cli php-common php-fpm php-gd php-curl php-xml php-mbstring; do
    pkg_install_rpm_if_missing "${pkg}"
  done
  if (( START_SERVICES )) && rpm -q httpd >/dev/null 2>&1; then
    service_restart httpd
  elif (( ! START_SERVICES )); then
    info "Service restarts disabled by --no-start"
  else
    info "httpd not installed yet — skipping Apache restart"
  fi
  ok "PHP installed with MySQL support"
fi

if (( WITH_INFO_PHP )); then
  (( INSTALL_PHP || rpm -q php >/dev/null 2>&1 )) || die "--with-info-php requires PHP to be installed"
  (( INSTALL_APACHE || rpm -q httpd >/dev/null 2>&1 )) || die "--with-info-php requires Apache to be installed"
  echo "<?php phpinfo(); ?>" > "${INFO_PHP}"
  chmod 644 "${INFO_PHP}"
  ok "Test file created at http://127.0.0.1/info.php"
  warn "Remove after testing: sudo ./dev/lamp_python_setup.sh --remove-info-php"
else
  info "Skipping info.php (use --with-info-php only for a one-time PHP smoke test)"
fi

if (( INSTALL_PYTHON_CONNECTORS )); then
  info "Installing Python and MySQL connectors..."
  pkg_install_if_missing python3
  pkg_install_if_missing python3-pip
  ensure_user_bin_on_path
  pkg_run_captured "Failed to upgrade user pip" pip \
    run_as_real_user_with_path python3 -m pip install --upgrade --user pip
  pkg_run_captured "Failed to install mysql-connector-python" pip \
    run_as_real_user_with_path python3 -m pip install --user mysql-connector-python
  pkg_run_captured "Failed to install SQLAlchemy/PyMySQL" pip \
    run_as_real_user_with_path python3 -m pip install --user SQLAlchemy PyMySQL
  ok "Python MySQL connectors installed (mysql.connector, SQLAlchemy, PyMySQL)"
fi

theme_section "Verification"
if (( INSTALL_APACHE )); then
  if pkg_binary_path httpd >/dev/null 2>&1 || pkg_present httpd apache; then
    theme_status_ok "Apache package available"
  else
    theme_status_warn "Apache command missing"
  fi
fi
if (( INSTALL_MARIADB )); then
  if pkg_binary_path mysql >/dev/null 2>&1; then
    theme_status_ok "MariaDB client available"
  else
    theme_status_warn "MariaDB client missing"
  fi
fi
if (( INSTALL_PHP )); then
  if pkg_binary_path php >/dev/null 2>&1; then
    theme_status_ok "PHP CLI available"
  else
    theme_status_warn "PHP CLI missing"
  fi
fi
if (( INSTALL_PYTHON_CONNECTORS )); then
  if run_as_real_user_with_path python3 -c "import mysql.connector" 2>/dev/null; then
    theme_status_ok "Python MySQL connector available"
  else
    theme_status_warn "Python MySQL connector missing"
  fi
fi

theme_result_ready "Requested web/database components resolved"
if (( START_SERVICES )) && { (( INSTALL_APACHE )) || rpm -q httpd >/dev/null 2>&1; }; then
  theme_note "Apache: http://127.0.0.1/"
fi
if (( START_SERVICES )) && { (( INSTALL_MARIADB )) || rpm -q mariadb-server >/dev/null 2>&1; }; then
  theme_note "MariaDB client: mysql -u root -p"
fi
theme_note "Detailed status: ./dev/web_stack_doctor.sh"
