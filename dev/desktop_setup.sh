#!/usr/bin/env bash
# desktop_setup.sh — Cinnamon primary desktop + optional alternate environments
# Version: 0.2.0
#
# Installs Fedora desktop profiles using group names when available, then
# package fallbacks. Default behavior installs Cinnamon plus GNOME/XFCE.
# See dev/README.md § Desktop environments.
#
# Run:
#   sudo ./dev/desktop_setup.sh
#   sudo ./dev/desktop_setup.sh --status
#   sudo ./dev/desktop_setup.sh --cinnamon-only
#   sudo ./dev/desktop_setup.sh --set-default

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/packages.sh
source "${_SCRIPT_DIR}/../lib/packages.sh"

STATUS_ONLY=0
SET_DEFAULT=0
DEFAULT_SESSION="cinnamon"
INSTALL_PROFILES=1
PROFILE_SELECTION_CHANGED=0

SELECTED_PROFILES=(cinnamon gnome xfce)

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
# shellcheck disable=SC2034
KDE_GROUPS=(
  kde-desktop
  '@kde-desktop-environment'
)
# shellcheck disable=SC2034
KDE_PKGS=(
  plasma-desktop sddm konsole dolphin
)
# shellcheck disable=SC2034
MATE_GROUPS=(
  '@mate-desktop'
  mate-desktop
)
# shellcheck disable=SC2034
MATE_PKGS=(
  mate-session-manager mate-panel caja pluma marco
)
# shellcheck disable=SC2034
LXQT_GROUPS=(
  '@lxqt-desktop'
  lxqt-desktop
)
# shellcheck disable=SC2034
LXQT_PKGS=(
  lxqt-session lxqt-panel pcmanfm-qt qterminal sddm
)
# shellcheck disable=SC2034
BUDGIE_GROUPS=(
  budgie-desktop
  '@budgie-desktop'
)
# shellcheck disable=SC2034
BUDGIE_PKGS=(
  budgie-desktop budgie-control-center nautilus gnome-terminal
)
# shellcheck disable=SC2034
COSMIC_GROUPS=(
  cosmic-desktop
  '@cosmic-desktop'
)
# shellcheck disable=SC2034
COSMIC_PKGS=(
  cosmic-session cosmic-files
)
# shellcheck disable=SC2034
SWAY_GROUPS=(
  swaywm-extended
  '@swaywm-extended'
)
# shellcheck disable=SC2034
SWAY_PKGS=(
  sway swaybg swaylock swayidle waybar foot
)

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Install desktop environments for $(real_user).
Default profiles: Cinnamon + GNOME + XFCE.

Available profiles:
  cinnamon, gnome, xfce, kde, mate, lxqt, budgie, cosmic, sway

Options:
  --help, -h          Show this help
  --status            List installed sessions (no install)
  --cinnamon-only     Install Cinnamon only
  --fallbacks-only    Install GNOME + XFCE only (skip Cinnamon)
  --profiles LIST     Add profiles (comma-separated)
  --only-profiles LIST  Replace default install set with profiles in LIST
  --set-default       Set Cinnamon as default session for $(real_user)
  --default-session NAME  Set default session name after install
  --skip-default      Do not change default session after install

Run with sudo for install/default. --status works without sudo.
EOF
}

parse_profiles_csv() {
  local csv="$1"
  local out_name="$2"
  local -n _out_ref="${out_name}"
  local item
  IFS=',' read -r -a _out_ref <<< "${csv}"
  for item in "${!_out_ref[@]}"; do
    _out_ref[$item]="$(printf '%s' "${_out_ref[$item]}" | tr '[:upper:]' '[:lower:]' | xargs)"
  done
}

desktop_normalize_session() {
  case "${1,,}" in
    cinnamon|cinnamon-wayland|cinnamon2d) printf 'cinnamon\n' ;;
    gnome|gnome-classic) printf 'gnome\n' ;;
    xfce|xfce4) printf 'xfce\n' ;;
    kde|plasma|plasma-desktop) printf 'plasma\n' ;;
    mate) printf 'mate\n' ;;
    lxqt) printf 'lxqt\n' ;;
    budgie|budgie-desktop) printf 'budgie-desktop\n' ;;
    cosmic) printf 'cosmic\n' ;;
    sway) printf 'sway\n' ;;
    *) printf '%s\n' "${1,,}" ;;
  esac
}

desktop_profile_known() {
  case "$1" in
    cinnamon|gnome|xfce|kde|mate|lxqt|budgie|cosmic|sway) return 0 ;;
    *) return 1 ;;
  esac
}

desktop_add_profile_list() {
  local profile
  for profile in "$@"; do
    [[ -n "${profile}" ]] || continue
    desktop_profile_known "${profile}" || die "Unknown desktop profile: ${profile}"
    if [[ " ${SELECTED_PROFILES[*]} " != *" ${profile} "* ]]; then
      SELECTED_PROFILES+=("${profile}")
    fi
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --status) STATUS_ONLY=1; shift ;;
    --cinnamon-only) SELECTED_PROFILES=(cinnamon); INSTALL_PROFILES=1; PROFILE_SELECTION_CHANGED=1; shift ;;
    --fallbacks-only) SELECTED_PROFILES=(gnome xfce); INSTALL_PROFILES=1; PROFILE_SELECTION_CHANGED=1; shift ;;
    --profiles)
      [[ $# -ge 2 ]] || die "--profiles requires a comma-separated value"
      _desktop_profiles=()
      parse_profiles_csv "$2" _desktop_profiles
      desktop_add_profile_list "${_desktop_profiles[@]}"
      INSTALL_PROFILES=1
      PROFILE_SELECTION_CHANGED=1
      shift 2
      ;;
    --only-profiles)
      [[ $# -ge 2 ]] || die "--only-profiles requires a comma-separated value"
      SELECTED_PROFILES=()
      _desktop_profiles=()
      parse_profiles_csv "$2" _desktop_profiles
      desktop_add_profile_list "${_desktop_profiles[@]}"
      INSTALL_PROFILES=1
      PROFILE_SELECTION_CHANGED=1
      shift 2
      ;;
    --set-default) SET_DEFAULT=1; shift ;;
    --default-session)
      [[ $# -ge 2 ]] || die "--default-session requires a session name"
      DEFAULT_SESSION="$(desktop_normalize_session "$2")"
      SET_DEFAULT=1
      shift 2
      ;;
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
  desktop_session_installed plasma && ok "KDE Plasma session available" \
    || warn "KDE Plasma session not found"
  desktop_session_installed mate && ok "MATE session available" \
    || warn "MATE session not found"
  desktop_session_installed lxqt && ok "LXQt session available" \
    || warn "LXQt session not found"
  desktop_session_installed budgie-desktop && ok "Budgie session available" \
    || warn "Budgie session not found"
  desktop_session_installed cosmic && ok "COSMIC session available" \
    || warn "COSMIC session not found"
  desktop_session_installed sway && ok "Sway session available" \
    || warn "Sway session not found"

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

desktop_install_named_profile() {
  local profile="$1"
  case "${profile}" in
    cinnamon) desktop_install_profile "Cinnamon (primary)" CINNAMON_GROUPS CINNAMON_PKGS ;;
    gnome) desktop_install_profile "GNOME" GNOME_GROUPS GNOME_PKGS ;;
    xfce) desktop_install_profile "XFCE" XFCE_GROUPS XFCE_PKGS ;;
    kde) desktop_install_profile "KDE Plasma" KDE_GROUPS KDE_PKGS ;;
    mate) desktop_install_profile "MATE" MATE_GROUPS MATE_PKGS ;;
    lxqt) desktop_install_profile "LXQt" LXQT_GROUPS LXQT_PKGS ;;
    budgie) desktop_install_profile "Budgie" BUDGIE_GROUPS BUDGIE_PKGS ;;
    cosmic) desktop_install_profile "COSMIC" COSMIC_GROUPS COSMIC_PKGS ;;
    sway) desktop_install_profile "Sway" SWAY_GROUPS SWAY_PKGS ;;
    *) die "Unknown desktop profile: ${profile}" ;;
  esac
}

desktop_set_default_session() {
  local session user home acct dmrc
  session="$(desktop_normalize_session "$1")"
  user="$(real_user)"
  home="$(real_home)"
  acct="/var/lib/AccountsService/users/${user}"

  if desktop_session_installed "${session}"; then
    ok "${session} session is installed"
  else
    warn "${session} session not found — default not changed"
    return 0
  fi

  if [[ -f "${acct}" ]]; then
    if rg -q '^XSession=' "${acct}" 2>/dev/null; then
      sed -i "s/^XSession=.*/XSession=${session}/" "${acct}"
    else
      printf '\nXSession=%s\n' "${session}" >> "${acct}"
    fi
    if rg -q '^Session=' "${acct}" 2>/dev/null; then
      sed -i "s/^Session=.*/Session=${session}/" "${acct}"
    else
      printf 'Session=%s\n' "${session}" >> "${acct}"
    fi
    ok "Set AccountsService default session to ${session} for ${user}"
  else
    warn "AccountsService file missing: ${acct} (skipped GDM default)"
  fi

  dmrc="${home}/.dmrc"
  if [[ -d "${home}" ]]; then
    cat > "${dmrc}" <<EOF
[Desktop]
Session=${session}
EOF
    chown "${user}:${user}" "${dmrc}" 2>/dev/null || true
    ok "Wrote ${dmrc} for LightDM"
  fi

  if have switchdesk; then
    switchdesk "${session}" 2>/dev/null || true
    ok "switchdesk ${session}"
  fi

  echo
  info "Log out and back in, or pick ${session} from the gear icon on the login screen."
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

  if dnf_installed sddm; then
    info "Enabling SDDM..."
    systemctl enable --now sddm.service
    ok "SDDM enabled"
    return 0
  fi

  warn "No display manager enabled — install/enable gdm, lightdm, or sddm if graphical login fails"
}

if (( STATUS_ONLY == 1 )); then
  desktop_show_status
  exit 0
fi

require_root "Run with sudo: sudo ./dev/desktop_setup.sh"
require_dnf
packages_preflight

if (( SET_DEFAULT == 1 )) && (( PROFILE_SELECTION_CHANGED == 0 )); then
  INSTALL_PROFILES=0
fi

if (( INSTALL_PROFILES == 1 )) && ((${#SELECTED_PROFILES[@]} == 0)); then
  die "No desktop profiles selected"
fi

if (( INSTALL_PROFILES == 0 )); then
  desktop_set_default_session "${DEFAULT_SESSION}"
  desktop_show_status
  exit 0
fi

for desktop_profile in "${SELECTED_PROFILES[@]}"; do
  desktop_install_named_profile "${desktop_profile}"
done

desktop_ensure_display_manager

if (( SET_DEFAULT != -1 )); then
  desktop_set_default_session "${DEFAULT_SESSION}"
fi

echo
desktop_show_status
