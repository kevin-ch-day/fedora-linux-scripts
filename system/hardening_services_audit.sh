#!/usr/bin/env bash
# hardening_services_audit.sh — read-only service review (Round 2 prep)
# Version: 0.3.0
#
# Profile-aware (desktop vs headless). Auto-detects host/OS/users.

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${_SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/hardening.sh
source "${FEDORA_ROOT}/lib/hardening.sh"
# shellcheck source=../lib/theme.sh
source "${FEDORA_ROOT}/lib/theme.sh"
theme_init

usage() {
  cat <<EOF
Usage: $(basename "$0") [--help]

Read-only, profile-aware audit of systemd services on this host.
Highlights Round 2 disable candidates based on desktop vs headless profile.

Also: ./system/system.sh services-audit
      System menu → [8] OS hardening → [2]

Toolkit root: ${FEDORA_ROOT}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

_is_enabled() {
  systemctl is-enabled --quiet "$1" 2>/dev/null
}

_is_active() {
  systemctl is-active --quiet "$1" 2>/dev/null
}

_unit_exists() {
  systemctl cat "$1" >/dev/null 2>&1
}

_unit_status_line() {
  local unit="$1"
  local en act
  en="disabled"; _is_enabled "${unit}" && en="enabled"
  act="inactive"; _is_active "${unit}" && act="active"
  printf '%s · %s' "${en}" "${act}"
}

theme_banner "Services audit"
hardening_print_host_banner_meta
theme_meta_line "Read-only — no changes"
theme_rule '─'
echo

hardening_preflight_or_warn || true
echo

if have firewall-cmd; then
  theme_section "Firewall zones (current)"
  theme_meta_line "Default zone: $(hardening_firewall_default_zone 2>/dev/null || echo unknown)"
  hardening_firewall_print_zone_summary "$(hardening_firewall_default_zone 2>/dev/null || echo public)" 2>/dev/null || true
  if hardening_round2_firewall_is_strict "$(hardening_firewall_default_zone 2>/dev/null || true)" 2>/dev/null; then
    ok "Firewall: strict profile (ssh only)"
  else
    warn "Firewall: workstation-style — consider ./system/hardening_round2.sh --yes"
  fi
  echo
fi

hardening_print_round1_status
echo
hardening_print_round2_status
echo

theme_section "Core services (installed / relevant on this host)"
while IFS= read -r unit; do
  [[ -n "${unit}" ]] || continue
  if ! _unit_exists "${unit}"; then
    info "${unit}: not installed"
    continue
  fi
  local_line="$(_unit_status_line "${unit}")"
  if [[ "${local_line}" == enabled* || "${local_line}" == *"· active"* ]]; then
    ok "${unit}: ${local_line}"
  else
    info "${unit}: ${local_line}"
  fi
done < <(hardening_core_service_units)

echo
theme_section "Round 2 candidates (profile: $(hardening_host_profile))"
found=0
skipped=0
while IFS='|' read -r unit reason profile_tag; do
  [[ -n "${unit}" ]] || continue
  if ! hardening_round2_relevant_for_profile "${profile_tag}"; then
    if _is_enabled "${unit}" || _is_active "${unit}"; then
      skipped=$((skipped + 1))
      info "${unit}: $(_unit_status_line "${unit}") — not flagged (profile: ${profile_tag})"
    fi
    continue
  fi
  if ! _unit_exists "${unit}"; then
    continue
  fi
  if _is_enabled "${unit}" || _is_active "${unit}"; then
    found=1
    warn "${unit}: $(_unit_status_line "${unit}")"
    theme_meta_line "  ${reason}"
  fi
done < <(hardening_round2_candidates)

if (( found == 0 )); then
  ok "No Round 2 candidates active for $(hardening_host_profile) profile"
fi
if (( skipped > 0 )); then
  theme_meta_line "${skipped} desktop-only unit(s) active but not flagged on this profile"
fi

echo
theme_section "SSH AllowUsers (detected on this host)"
theme_meta_line "  Mode auto:   $(hardening_detect_ssh_allow_users)"
theme_meta_line "  Mode wheel:  $(hardening_detect_wheel_users 2>/dev/null || echo '(no wheel login users)')"
existing="$(hardening_sshd_effective_allow_users 2>/dev/null || true)"
if [[ -n "${existing}" ]]; then
  theme_meta_line "  sshd now:    ${existing}"
fi
echo
theme_meta_line "Login accounts (/home/*):"
while IFS=: read -r u _ uid _ _ home shell; do
  [[ "${uid}" =~ ^[0-9]+$ ]] || continue
  (( uid >= 1000 && uid < 60000 )) || continue
  hardening_is_human_home "${home}" || continue
  hardening_has_login_shell "${shell}" || continue
  local wheel_mark=""
  getent group wheel 2>/dev/null | grep -qF "${u}" && wheel_mark=" · wheel"
  theme_meta_line "  ${u} (uid ${uid})${wheel_mark} · ${home}"
done < <(getent passwd 2>/dev/null || true)

echo
theme_section "Research stack (toolkit-related)"
for pkg_unit in mariadb httpd php-fpm docker podman; do
  case "${pkg_unit}" in
    mariadb) hardening_package_installed mariadb-server || hardening_package_installed mariadb || continue ;;
    httpd) hardening_package_installed httpd || continue ;;
    php-fpm) hardening_package_installed php-fpm || continue ;;
    docker) hardening_package_installed docker-ce || hardening_package_installed moby-engine || continue ;;
    podman) hardening_package_installed podman || continue ;;
  esac
  if _unit_exists "${pkg_unit}"; then
    info "${pkg_unit}: $(_unit_status_line "${pkg_unit}")"
  fi
done

echo
theme_section "Enabled services (count)"
enabled_count="$(systemctl list-unit-files --type=service --state=enabled --no-legend 2>/dev/null | wc -l | tr -d ' ')"
running_count="$(systemctl list-units --type=service --state=running --no-legend 2>/dev/null | wc -l | tr -d ' ')"
theme_meta_line "  Enabled: ${enabled_count:-?} · Running: ${running_count:-?}"
theme_meta_line "  Full list: systemctl list-unit-files --type=service --state=enabled"

echo
theme_summary_box "Services audit complete" \
  "Host:     $(health_hostname)" \
  "Profile:  $(hardening_host_profile)" \
  "Changes:  none (read-only)" \
  "Next:     review Round 2 candidates, then discuss disables"
