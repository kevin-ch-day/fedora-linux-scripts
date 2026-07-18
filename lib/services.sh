#!/usr/bin/env bash
# lib/services.sh — systemd and common service visibility helpers
# Version: 0.2.6
#
# Do not execute directly.

if [[ -n "${FEDORA_SERVICES_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_SERVICES_SH_LOADED=1

_SVC_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_SVC_LIB_DIR}/common.sh"
# shellcheck source=health.sh
source "${_SVC_LIB_DIR}/health.sh"

# ---------- generic systemd ----------
service_unit_active() {
  local unit="$1" out
  have systemctl || { printf 'unknown\n'; return 1; }
  out="$(systemctl is-active "${unit}" 2>/dev/null | head -n 1)" || true
  [[ -n "${out}" ]] || out=inactive
  printf '%s\n' "${out}"
}

service_unit_enabled() {
  local unit="$1" out
  have systemctl || { printf 'unknown\n'; return 1; }
  out="$(systemctl is-enabled "${unit}" 2>/dev/null | head -n 1)" || true
  [[ -n "${out}" ]] || out=disabled
  printf '%s\n' "${out}"
}

service_status_line() {
  local unit="$1"
  local label="${2:-${unit}}"
  printf '  %-14s active=%-12s enabled=%s\n' \
    "${label}:" \
    "$(service_unit_active "${unit}")" \
    "$(service_unit_enabled "${unit}")"
}

service_enable_now() {
  local unit="$1"
  have systemctl || die "systemctl not available"
  if [[ "${EUID}" -eq 0 ]]; then
    systemctl enable --now "${unit}" 2>/dev/null || warn "${unit} not enabled (package may be absent)"
  else
    sudo systemctl enable --now "${unit}" 2>/dev/null || warn "${unit} not enabled (package may be absent)"
  fi
}

service_restart() {
  local unit="$1"
  have systemctl || die "systemctl not available"
  if [[ "${EUID}" -eq 0 ]]; then
    systemctl restart "${unit}"
  else
    sudo systemctl restart "${unit}"
  fi
}

services_show_failed_units() {
  echo "Failed systemd units:"
  local failed
  failed="$(health_failed_systemd_units_count)"
  echo "  Count: ${failed}"
  if [[ "${failed}" != "0" ]]; then
    health_failed_systemd_units_list | sed 's/^/  /'
  fi
}

# ---------- common stack services ----------
services_status_web_stack() {
  echo "Web stack:"
  service_status_line httpd "Apache (httpd)"
  service_status_line mariadb "MariaDB"
  service_status_line php-fpm "PHP-FPM"
}

services_status_containers() {
  echo "Containers:"
  service_status_line docker "Docker"
  service_status_line podman "Podman"
  if cmd_available podman; then
    printf '  %-14s %s\n' "Podman info:" "$(podman info --format '{{.Host.OS}}' 2>/dev/null || echo unavailable)"
  fi
}

services_status_virtualization() {
  echo "Virtualization:"
  service_status_line libvirtd "libvirtd"
}

services_status_virtualization_stack() {
  echo "Virtualization & containers:"
  services_status_containers
  echo
  services_status_virtualization
}

web_stack_http_code() {
  local url="$1"
  curl -sS -o /dev/null -w '%{http_code}' --max-time 3 "${url}" 2>/dev/null || printf '000'
}

web_stack_doctor() {
  local rc=0
  local web_stack_installed=0

  common_init_colors
  theme_set_lane dev
  theme_report_header "Web stack doctor" "LAMP · MariaDB · PHP · phpMyAdmin"
  health_print_runtime_awareness
  echo
  services_status_web_stack
  echo

  if rpm -q httpd >/dev/null 2>&1 \
     || rpm -q mariadb-server >/dev/null 2>&1 \
     || rpm -q php >/dev/null 2>&1 \
     || rpm -q phpMyAdmin >/dev/null 2>&1; then
    web_stack_installed=1
  fi

  if have systemctl; then
    if [[ "$(service_unit_active httpd)" != "active" ]]; then
      warn "httpd is not active"
      rc=1
    fi
    if [[ "$(service_unit_active mariadb)" != "active" ]]; then
      warn "mariadb is not active"
      rc=1
    fi
  fi

  if cmd_available curl; then
    local root_code info_code pma_code
    root_code="$(web_stack_http_code http://127.0.0.1/)"
    case "${root_code}" in
      2*|3*|401|403) ok "http://127.0.0.1/ reachable (HTTP ${root_code})" ;;
      *)
        warn "http://127.0.0.1/ not reachable (HTTP ${root_code})"
        rc=1
        ;;
    esac

    info_code="$(web_stack_http_code http://127.0.0.1/info.php)"
    case "${info_code}" in
      2*|3*|401|403)
        warn "http://127.0.0.1/info.php reachable (HTTP ${info_code}) — remove after testing (phpinfo disclosure)"
        warn "  sudo ./dev/lamp_python_setup.sh --remove-info-php"
        ;;
      *)
        ok "info.php not exposed (HTTP ${info_code}; good — or run lamp setup with --with-info-php to test PHP)"
        ;;
    esac

    pma_code="$(web_stack_http_code http://127.0.0.1/phpmyadmin/)"
    case "${pma_code}" in
      2*|3*|401|403) ok "http://127.0.0.1/phpmyadmin/ reachable (HTTP ${pma_code})" ;;
      404) warn "http://127.0.0.1/phpmyadmin/ returns 404 (optional — run phpmyadmin_setup.sh)" ;;
      *)
        warn "http://127.0.0.1/phpmyadmin/ not reachable (HTTP ${pma_code}; optional — run phpmyadmin_setup.sh)"
        ;;
    esac
  else
    warn "curl not installed; skipping HTTP checks"
  fi

  echo
  local db_client_bin php_bin
  if db_client_bin="$(cmd_binary_path mariadb 2>/dev/null)"; then
    ok "mariadb client: $("${db_client_bin}" --version 2>&1 | head -n 1)"
  elif db_client_bin="$(cmd_binary_path mysql 2>/dev/null)"; then
    ok "mysql client: $("${db_client_bin}" --version 2>&1 | head -n 1)"
  else
    if (( web_stack_installed == 0 )); then
      warn "MariaDB client not installed yet (run lamp_python_setup.sh)"
    else
      warn "MariaDB client not on PATH"
    fi
    rc=1
  fi
  if php_bin="$(cmd_binary_path php 2>/dev/null)"; then
    ok "php: $("${php_bin}" -v 2>&1 | head -n 1)"
  else
    if (( web_stack_installed == 0 )); then
      warn "php CLI not installed yet (run lamp_python_setup.sh)"
    else
      warn "php not on PATH"
    fi
    rc=1
  fi
  echo
  theme_rule '─'
  if (( rc == 0 )); then
    ok "Web stack doctor: READY"
  else
    warn "Web stack doctor: ISSUES"
  fi
  return "${rc}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
