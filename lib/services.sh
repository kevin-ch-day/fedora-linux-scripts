#!/usr/bin/env bash
# lib/services.sh — systemd and common service visibility helpers
# Version: 0.2.5
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
  if have podman; then
    printf '  %-14s %s\n' "Podman info:" "$(podman info --format '{{.Host.OS}}' 2>/dev/null || echo unavailable)"
  fi
}

services_status_virtualization() {
  echo "Virtualization:"
  service_status_line libvirtd "libvirtd"
}

services_status_research_stack() {
  echo "Research workstation services:"
  services_status_web_stack
  echo
  services_status_containers
  echo
  services_status_virtualization
  echo
  echo "MobSF (static analysis stack):"
  services_mobsf_brief
}

services_mobsf_brief() {
  local root mobsf_lib
  root="$(fedora_toolkit_root)"
  mobsf_lib="${root}/mobsf/lib/mobsf.sh"
  if [[ ! -f "${mobsf_lib}" ]]; then
    warn "MobSF: lib not found under ${root}/mobsf/"
    return 0
  fi
  # shellcheck source=../../mobsf/lib/mobsf.sh
  source "${mobsf_lib}"
  mobsf_doctor_brief || true
}

web_stack_doctor() {
  local rc=0

  echo "============================================================"
  echo "Web stack doctor (LAMP / phpMyAdmin)"
  echo "============================================================"
  echo
  services_status_web_stack
  echo

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

  if have curl; then
    if curl -fsS -o /dev/null --max-time 3 http://127.0.0.1/ 2>/dev/null; then
      ok "http://127.0.0.1/ reachable"
    else
      warn "http://127.0.0.1/ not reachable"
      rc=1
    fi
    if curl -fsS -o /dev/null --max-time 3 http://127.0.0.1/info.php 2>/dev/null; then
      warn "http://127.0.0.1/info.php reachable — remove after testing (phpinfo disclosure)"
      warn "  sudo ./dev/lamp_python_setup.sh --remove-info-php"
    else
      ok "info.php not exposed (good — or run lamp setup with --with-info-php to test PHP)"
    fi
    if curl -fsS -o /dev/null --max-time 3 http://127.0.0.1/phpmyadmin/ 2>/dev/null; then
      ok "http://127.0.0.1/phpmyadmin/ reachable"
    else
      warn "http://127.0.0.1/phpmyadmin/ not reachable (optional — run phpmyadmin_setup.sh)"
    fi
  else
    warn "curl not installed; skipping HTTP checks"
  fi

  echo
  if have mysql; then
    ok "mysql client: $(mysql --version 2>&1 | head -n 1)"
  else
    warn "mysql client not on PATH"
    rc=1
  fi
  if have php; then
    ok "php: $(php -v 2>&1 | head -n 1)"
  else
    warn "php not on PATH"
    rc=1
  fi
  echo "============================================================"
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
