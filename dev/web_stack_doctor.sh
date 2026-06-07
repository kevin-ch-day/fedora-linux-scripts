#!/usr/bin/env bash
# web_stack_doctor.sh — Check Apache/MariaDB/PHP/phpMyAdmin health
# Version: 0.2.0
#
# Run:
#   ./dev/web_stack_doctor.sh
#   ./dev/web_stack_doctor.sh --help

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/services.sh
source "${_SCRIPT_DIR}/../lib/services.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

HTTP and service checks for the LAMP / phpMyAdmin dev stack:
  httpd, mariadb, php-fpm status; curl probes to 127.0.0.1; mysql/php clients.

Options:
  --help, -h     Show this help

Exit code: 0 if core checks pass, 1 if issues found.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
done

web_stack_doctor
