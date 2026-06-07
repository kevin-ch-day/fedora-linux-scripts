#!/usr/bin/env bash
# desktop_setup.sh — Cinnamon primary desktop + fallback environments
# Version: 0.1.0
#
# Run:
#   sudo ./dev/desktop_setup.sh
#   sudo ./dev/desktop_setup.sh --status
#   sudo ./dev/desktop_setup.sh --cinnamon-only
#   sudo ./dev/desktop_setup.sh --fallbacks-only
#   sudo ./dev/desktop_setup.sh --set-default

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/packages.sh
source "${_SCRIPT_DIR}/../lib/packages.sh"

INSTALL_CINNAMON=1
INSTALL_FALLBACKS=1
SET_DEFAULT=0
STATUS_ONLY=0

# DNF group identifiers (first match wins). Used via nameref in desktop_install_profile.
# shellcheck disable=SC2034
CINNAMON_GROUPS=(
  '@cinnamon-desktop'
  '@cinnamon-desktop-environment'
  cinnamon-desktop
)
# shellcheck disable=SC2034
GNOME_GROUPS=(
  '@gnome-desktop'
  '@gnome-desktop-environment'
  '@workstation-product-environment'
  gnome-desktop
)
# shellcheck disable=SC2034
XFCE_GROUPS=(
  '@xfce-desktop'
  '@xfce-desktop-environment'
  xfce-desktop
)

# Package fallbacks when environment groups are unavailable.
# shellcheck disable=SC2034
CINNAMON_PKGS=(
  cinnamon cinnamon-session cinnamon-control-center cinnamon-settings-daemon
  nemo muffin xapps slick-greeter-cinnamon
)
# shellcheck disable=SC2034
GNOME_PKGS=(
  gnome-shell gnome-session gnome-terminal nautilus
)
# shellcheck disable=SC2034
XFCE_PKGS=(
  xfce4-session xfce4-panel xfce4-terminal thunar
)

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Install desktop environments for $(real_user):
  Primary:  Cinnamon (recommended)
  Fallback: GNOME, XFCE (login-screen session picker)

Options:
  --help, -h          Show this help
  --status            List installed sessions (no install)
  --cinnamon-only     Install Cinnamon only
  --fallbacks-only    Install GNOME + XFCE only (skip Cinnamon)
  --set-default       Set Cinnamon as default session for $(real_user)
  --skip-default      Do not set Cinnamon as default after install

Run with sudo for install/default. --status works without sudo.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --status) STATUS_ONLY=1; shift ;;
    --cinnamon-only) INSTALL_FALLBACKS=0; shift ;;
    --fallbacks-only) INSTALL_CINNAMON=0; shift ;;
    --set-default) SET_DEFAULT=1; shift ;;
    --skip-default) SET_DEFAULT=-1; shift ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
done

desktop_session_installed() {
  local session="$1"
  [[ -f "/usr/share/xsessions/${session}.desktop" ]] \
    || [[ -f "/usr/share/wayland-sessions/${session}.desktop" ]]
}

desktop_list_sessions() {
  local f base
  shopt -s nullglob
  for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
    base="$(basename "${f}" .desktop)"
    printf '  %s\n' "${base}"
  done | sort -u
  shopt -u nullglob
}

desktop_show_status() {
  info "Installed login sessions:"
  desktop_list_sessions || warn "No session .desktop files found under /usr/share"

  echo
  info "Quick probe:"
  desktop_session_installed cinnamon && ok "Cinnamon session available" \
    || warn "Cinnamon session not found"
  desktop_session_installed gnome && ok "GNOME session available" \
    || warn "GNOME session not found"
  desktop_session_installed xfce && ok "XFCE session available" \
    || warn "XFCE session not found"

  local user home acct
  user="$(real_user)"
  home="$(real_home)"
  acct="/var/lib/AccountsService/users/${user}"
  echo
  if [[ -f "${acct}" ]]; then
    info "AccountsService default for ${user}:"
    rg -n '^(XSession|Session)=' "${acct}" 2>/dev/null || echo "  (no XSession/Session set)"
  fi
  if [[ -f "${home}/.dmrc" ]]; then
    info "LightDM ~/.dmrc for ${user}:"
    sed -n '1,6p' "${home}/.dmrc"
  fi

  if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
    echo
    info "Current desktop (this shell): ${XDG_CURRENT_DESKTOP}"
  fi
}

# Try dnf environment groups, then plain group name, then individual packages.
desktop_install_profile() {
  local label="$1"
  local -n _groups_ref="$2"
  local -n _pkgs_ref="$3"
  local g plain missing=()

  for g in "${_groups_ref[@]}"; do
    if dnf -q list --available "${g}" >/dev/null 2>&1; then
      info "Installing ${label} (${g})..."
      pkg_dnf_run "Failed to install ${label} (${g})" install "${g}"
      ok "${label} installed via ${g}"
      return 0
    fi
  done

  for g in "${_groups_ref[@]}"; do
    plain="${g#@}"
    if dnf -q group list "${plain}" >/dev/null 2>&1; then
      info "Installing ${label} (group ${plain})..."
      pkg_dnf_run "Failed to install ${label} (group ${plain})" group install "${plain}"
      ok "${label} installed via group ${plain}"
      return 0
    fi
  done

  warn "${label}: no DNF group found — installing core packages"
  pkg_install_batch_if_available missing "${_pkgs_ref[@]}"
  if ((${#missing[@]} > 0)); then
    warn "${label}: some packages unavailable: ${missing[*]}"
  fi
}

desktop_set_cinnamon_default() {
  local user home acct dmrc
  user="$(real_user)"
  home="$(real_home)"
  acct="/var/lib/AccountsService/users/${user}"

  if desktop_session_installed cinnamon; then
    ok "Cinnamon session is installed"
  else
    warn "Cinnamon session not found — default not changed"
    return 0
  fi

  if [[ -f "${acct}" ]]; then
    if rg -q '^XSession=' "${acct}" 2>/dev/null; then
      sed -i 's/^XSession=.*/XSession=cinnamon/' "${acct}"
    else
      printf '\nXSession=cinnamon\n' >> "${acct}"
    fi
    if rg -q '^Session=' "${acct}" 2>/dev/null; then
      sed -i 's/^Session=.*/Session=cinnamon/' "${acct}"
    else
      printf 'Session=cinnamon\n' >> "${acct}"
    fi
    ok "Set AccountsService default session to cinnamon for ${user}"
  else
    warn "AccountsService file missing: ${acct} (skipped GDM default)"
  fi

  dmrc="${home}/.dmrc"
  if [[ -d "${home}" ]]; then
    cat > "${dmrc}" <<EOF
[Desktop]
Session=cinnamon
EOF
    chown "${user}:${user}" "${dmrc}" 2>/dev/null || true
    ok "Wrote ${dmrc} for LightDM"
  fi

  if have switchdesk; then
    switchdesk cinnamon 2>/dev/null || true
    ok "switchdesk cinnamon"
  fi

  echo
  info "Log out and back in, or pick Cinnamon from the gear icon on the login screen."
}

desktop_ensure_display_manager() {
  if systemctl is-enabled gdm.service >/dev/null 2>&1 \
     || systemctl is-enabled lightdm.service >/dev/null 2>&1 \
     || systemctl is-enabled sddm.service >/dev/null 2>&1; then
    ok "A display manager is already enabled"
    return 0
  fi

  if dnf_installed gdm; then
    info "Enabling GDM..."
    systemctl enable --now gdm.service
    ok "GDM enabled"
    return 0
  fi

  if dnf_installed lightdm; then
    info "Enabling LightDM..."
    systemctl enable --now lightdm.service
    ok "LightDM enabled"
    return 0
  fi

  warn "No display manager enabled — install/enable gdm or lightdm if graphical login fails"
}

if (( STATUS_ONLY == 1 )); then
  desktop_show_status
  exit 0
fi

require_root "Run with sudo: sudo ./dev/desktop_setup.sh"
require_dnf
packages_preflight

if (( SET_DEFAULT == 1 )) && (( INSTALL_CINNAMON == 0 )) && (( INSTALL_FALLBACKS == 0 )); then
  desktop_set_cinnamon_default
  desktop_show_status
  exit 0
fi

if (( INSTALL_CINNAMON == 1 )); then
  desktop_install_profile "Cinnamon (primary)" CINNAMON_GROUPS CINNAMON_PKGS
fi

if (( INSTALL_FALLBACKS == 1 )); then
  desktop_install_profile "GNOME (fallback)" GNOME_GROUPS GNOME_PKGS
  desktop_install_profile "XFCE (fallback)" XFCE_GROUPS XFCE_PKGS
fi

desktop_ensure_display_manager

if (( SET_DEFAULT != -1 )); then
  desktop_set_cinnamon_default
fi

echo
desktop_show_status
