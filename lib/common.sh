#!/usr/bin/env bash
# lib/common.sh — shared Fedora toolkit helpers
# Version: 0.2.5
#
# Source from task scripts:
#   _dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck source=../lib/common.sh
#   source "${_dir}/../lib/common.sh"
#
# Do not execute directly.

if [[ -n "${FEDORA_COMMON_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_COMMON_SH_LOADED=1

# ---------- paths (set when sourced) ----------
_FEDORA_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
_FEDORA_TOOLKIT_ROOT="$(cd -- "${_FEDORA_LIB_DIR}/.." && pwd)"

fedora_toolkit_root() {
  printf '%s\n' "${_FEDORA_TOOLKIT_ROOT}"
}

fedora_script_dir() {
  local src="${1:-${BASH_SOURCE[1]:-}}"
  [[ -n "${src}" ]] || die "fedora_script_dir: could not determine caller script"
  cd -- "$(dirname -- "${src}")" && pwd
}

# ---------- command checks ----------
have() {
  command -v "$1" >/dev/null 2>&1
}

# Resolve a binary on PATH or under standard sbin/bin dirs (sudo-safe).
cmd_binary_path() {
  local bin="$1"
  local p dir
  p="$(command -v "${bin}" 2>/dev/null || true)"
  [[ -n "${p}" ]] && { printf '%s\n' "${p}"; return 0; }
  for dir in /usr/bin /usr/sbin /sbin /bin; do
    [[ -x "${dir}/${bin}" ]] && { printf '%s/%s\n' "${dir}" "${bin}"; return 0; }
  done
  return 1
}

cmd_available() {
  cmd_binary_path "$1" >/dev/null 2>&1
}

# ---------- messaging (themed when TTY + colors enabled) ----------
_msg_maybe_init_theme() {
  [[ -t 1 || -t 2 ]] || return 0
  [[ -n "${NO_COLOR:-}" || "${FEDORA_NO_COLOR:-}" == 1 ]] && return 0
  if [[ -z "${FEDORA_THEME_SH_LOADED:-}" ]]; then
    # shellcheck source=theme.sh
    source "${_FEDORA_LIB_DIR}/theme.sh"
  fi
  if [[ "${THEME_USE_COLOR:-0}" -eq 0 ]]; then
    theme_init
  fi
}

die() {
  _msg_maybe_init_theme
  err "$@"
  exit 1
}

info() {
  _msg_maybe_init_theme
  if [[ "${THEME_USE_COLOR:-0}" -eq 1 ]]; then
    theme_msg_info "$*"
  else
    printf '[INFO] %s\n' "$*"
  fi
}

ok() {
  _msg_maybe_init_theme
  if [[ "${THEME_USE_COLOR:-0}" -eq 1 ]]; then
    theme_msg_ok "$*"
  else
    printf '[OK]   %s\n' "$*"
  fi
}

warn() {
  _msg_maybe_init_theme
  if [[ "${THEME_USE_COLOR:-0}" -eq 1 ]]; then
    theme_msg_warn "$*"
  else
    printf '[WARN] %s\n' "$*"
  fi
}

err() {
  _msg_maybe_init_theme
  if [[ "${THEME_USE_COLOR:-0}" -eq 1 ]]; then
    theme_msg_err "$*"
  else
    printf '[ERROR] %s\n' "$*" >&2
  fi
}

# ---------- colors (TTY-safe; empty when not a terminal) ----------
common_init_colors() {
  if [[ -z "${FEDORA_THEME_SH_LOADED:-}" ]]; then
    # shellcheck source=theme.sh
    source "${_FEDORA_LIB_DIR}/theme.sh"
  fi
  if declare -f theme_init >/dev/null 2>&1; then
    theme_init
  fi
}

# ---------- privilege / user context ----------
require_root() {
  local msg="${1:-Run with sudo.}"
  [[ "${EUID}" -eq 0 ]] || die "${msg}"
}

require_not_root() {
  local msg="${1:-Do not run as root.}"
  [[ "${EUID}" -ne 0 ]] || die "${msg}"
}

require_invoker_user() {
  local msg="${1:-Run as your normal user, not root.}"
  if [[ "${EUID}" -eq 0 && -z "${SUDO_USER:-}" ]]; then
    die "${msg}"
  fi
}

real_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != root ]]; then
    printf '%s\n' "${SUDO_USER}"
  else
    id -un 2>/dev/null || printf 'root\n'
  fi
}

real_home() {
  local user home
  user="$(real_user)"
  home="$(getent passwd "${user}" 2>/dev/null | cut -d: -f6 || true)"
  if [[ -n "${home}" ]]; then
    printf '%s\n' "${home}"
  else
    printf '%s\n' "${HOME}"
  fi
}

run_as_real_user() {
  local user
  user="$(real_user)"
  if [[ "$(id -un)" == "${user}" ]]; then
    "$@"
  else
    sudo -u "${user}" -H "$@"
  fi
}

# Add user to a supplementary group if the group exists (idempotent).
user_add_supplementary_group() {
  local user group
  user="${1:?user required}"
  group="${2:?group required}"
  getent group "${group}" >/dev/null 2>&1 || return 0
  if id -nG "${user}" | tr ' ' '\n' | grep -qx "${group}"; then
    ok "${user} already in ${group} group"
    return 0
  fi
  if [[ "${EUID}" -eq 0 ]]; then
    usermod -aG "${group}" "${user}"
  else
    sudo usermod -aG "${group}" "${user}"
  fi
  ok "Added ${user} to ${group} group (log out/in to apply)"
}

need_cmd() {
  cmd_available "$1" || die "Missing required command: $1"
}

# Ensure ~/.local/bin exists and is on PATH in the real user's ~/.bashrc.
ensure_user_bin_on_path() {
  local user home bashrc userbin
  local marker_begin="# >>> USER LOCAL BIN (managed) >>>"

  user="$(real_user)"
  home="$(real_home)"
  bashrc="${home}/.bashrc"
  userbin="${home}/.local/bin"

  run_as_real_user mkdir -p "${userbin}"

  if run_as_real_user bash -lc 'case ":$PATH:" in *":$HOME/.local/bin:"*) exit 0;; *) exit 1;; esac'; then
    ok "${home}/.local/bin already in PATH for ${user}"
    return 0
  fi

  if [[ -f "${bashrc}" ]] && grep -qF "${marker_begin}" "${bashrc}"; then
    ok "${home}/.local/bin PATH block already present"
    return 0
  fi

  info "Adding ${home}/.local/bin to PATH in ${bashrc}"
  cat >> "${bashrc}" <<'EOF'

# >>> USER LOCAL BIN (managed) >>>
export PATH="$HOME/.local/bin:$PATH"
# <<< USER LOCAL BIN (managed) <<<
EOF
  if [[ "${EUID}" -eq 0 ]]; then
    chown "${user}:${user}" "${bashrc}" 2>/dev/null || true
  fi
  ok "${home}/.local/bin PATH block added"
}

# ---------- filesystem / interaction ----------
ensure_dir() {
  local dir="$1"
  [[ -n "${dir}" ]] || die "ensure_dir: empty path"
  mkdir -p "${dir}"
}

confirm() {
  local prompt="${1:-Continue?}"
  local ans=""
  read -r -p "${prompt} [y/N] " ans
  case "${ans,,}" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

pause_return() {
  read -r -p "Press Enter to continue..."
}

common_init_colors

# Error helpers (traps, run_or_die, assert_*, dnf checks) — loaded for all toolkit scripts.
if [[ -z "${FEDORA_ERRORS_SH_LOADED:-}" ]]; then
  # shellcheck source=errors.sh
  source "${_FEDORA_LIB_DIR}/errors.sh"
fi

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
