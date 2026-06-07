#!/usr/bin/env bash
# lib/users.sh — local account, session, and privilege context
# Version: 0.1.0
#
# Read-only helpers for who is on the host and how they connect.
# Source after lib/common.sh.

if [[ -n "${FEDORA_USERS_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_USERS_SH_LOADED=1

_USERS_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_USERS_LIB_DIR}/common.sh"

# ---------- account classification ----------
users_has_login_shell() {
  local shell="$1"
  [[ -n "${shell}" ]] || return 1
  case "${shell}" in
    */nologin|*/false|/sbin/nologin|/usr/sbin/nologin) return 1 ;;
    *) return 0 ;;
  esac
}

users_is_human_home() {
  local home="$1"
  [[ "${home}" == /home/* ]]
}

users_is_system_account() {
  local uid="$1"
  [[ "${uid}" =~ ^[0-9]+$ ]] || return 0
  (( uid < 1000 || uid >= 60000 ))
}

users_add_unique() {
  local -n _arr=$1
  local -n _seen=$2
  local name="$3"
  [[ -n "${name}" && "${name}" != root ]] || return 0
  case " ${_seen} " in
    *" ${name} "*) return 0 ;;
  esac
  _arr+=("${name}")
  _seen+=" ${name}"
}

users_sorted_line() {
  local -a names=("$@")
  local IFS=$'\n'
  printf '%s\n' "$(printf '%s\n' "${names[@]}" | sort -u | tr '\n' ' ' | sed 's/ $//')"
}

users_merge_lists() {
  local -a names=()
  local seen="" part u
  for part in "$@"; do
    [[ -n "${part}" ]] || continue
    for u in ${part}; do
      users_add_unique names seen "${u}"
    done
  done
  if ((${#names[@]} == 0)); then
    printf '%s\n' "$(real_user)"
    return 0
  fi
  users_sorted_line "${names[@]}"
}

# Emit: user:uid:gid:home:shell (login-capable /home accounts, uid 1000–59999)
users_foreach_login_account() {
  local u uid gid home shell
  while IFS=: read -r u _ uid gid _ home shell; do
    [[ "${uid}" =~ ^[0-9]+$ ]] || continue
    (( uid >= 1000 && uid < 60000 )) || continue
    users_is_human_home "${home}" || continue
    users_has_login_shell "${shell}" || continue
    printf '%s:%s:%s:%s:%s\n' "${u}" "${uid}" "${gid}" "${home}" "${shell}"
  done < <(getent passwd 2>/dev/null || true)
}

# Space-separated login usernames; always includes invoker.
users_detect_login() {
  local -a names=()
  local seen="" invoker line u
  invoker="$(real_user)"
  users_add_unique names seen "${invoker}"

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    u="${line%%:*}"
    users_add_unique names seen "${u}"
  done < <(users_foreach_login_account)

  if ((${#names[@]} == 0)); then
    printf '%s\n' "${invoker}"
    return 0
  fi
  users_sorted_line "${names[@]}"
}

users_detect_wheel() {
  local -a names=()
  local seen="" members u uid home shell
  members="$(getent group wheel 2>/dev/null | cut -d: -f4 | tr ',' '\n' || true)"
  [[ -n "${members}" ]] || return 1

  while IFS= read -r u; do
    [[ -n "${u}" ]] || continue
    IFS=: read -r _ _ uid _ _ home shell _ <<< "$(getent passwd "${u}" 2>/dev/null || true)"
    users_has_login_shell "${shell}" || continue
    users_is_human_home "${home}" || continue
    users_add_unique names seen "${u}"
  done <<< "${members}"

  ((${#names[@]} > 0)) || return 1
  users_sorted_line "${names[@]}"
}

users_detect_sudo_capable() {
  local -a names=()
  local seen="" u
  if users_detect_wheel >/dev/null 2>&1; then
    while read -r u; do
      [[ -n "${u}" ]] || continue
      users_add_unique names seen "${u}"
    done < <(users_detect_wheel | tr ' ' '\n')
  fi
  if getent group sudo >/dev/null 2>&1; then
    while IFS= read -r u; do
      [[ -n "${u}" ]] || continue
      users_add_unique names seen "${u}"
    done < <(getent group sudo 2>/dev/null | cut -d: -f4 | tr ',' '\n')
  fi
  ((${#names[@]} > 0)) || return 1
  users_sorted_line "${names[@]}"
}

# auto: wheel if any, else login; always includes invoker.
users_detect_ssh_allow_candidates() {
  local invoker wheel login
  invoker="$(real_user)"
  wheel="$(users_detect_wheel 2>/dev/null || true)"
  if [[ -n "${wheel}" ]]; then
    users_merge_lists "${wheel}" "${invoker}"
    return 0
  fi
  login="$(users_detect_login)"
  users_merge_lists "${login}" "${invoker}"
}

# Modes: auto | wheel | login | explicit user list
users_normalize_allow_list() {
  local raw="${1:-}"
  raw="${raw//,/ }"
  raw="$(echo "${raw}" | tr -s ' ' | sed 's/^ //;s/ $//')"
  case "${raw}" in
    ""|auto) users_detect_ssh_allow_candidates ;;
    wheel) users_detect_wheel 2>/dev/null || users_detect_login ;;
    login) users_detect_login ;;
    *) users_merge_lists "${raw}" "$(real_user)" ;;
  esac
}

users_allow_mode_label() {
  local mode="${1:-auto}"
  [[ -n "${mode}" ]] || mode="auto"
  case "${mode}" in
    auto) printf 'auto (wheel admins if present, else login users)\n' ;;
    wheel) printf 'wheel (sudo/wheel group only)\n' ;;
    login) printf 'login (/home/* interactive accounts)\n' ;;
    *) printf 'explicit (%s)\n' "${mode}" ;;
  esac
}

# ---------- session / connection ----------
# local | ssh | headless | unknown
users_session_kind() {
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    printf 'ssh\n'
    return 0
  fi
  if [[ -n "${XDG_CURRENT_DESKTOP:-}" || -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]; then
    printf 'local\n'
    return 0
  fi
  if systemctl is-active --quiet gdm 2>/dev/null \
    || systemctl is-active --quiet sddm 2>/dev/null \
    || systemctl is-active --quiet lightdm 2>/dev/null; then
    printf 'local\n'
    return 0
  fi
  if loginctl list-sessions --no-legend 2>/dev/null | grep -q .; then
    if loginctl list-sessions --no-legend 2>/dev/null | awk '{print $4}' | grep -qiE 'seat|tty'; then
      printf 'local\n'
      return 0
    fi
  fi
  if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    printf 'headless\n'
    return 0
  fi
  printf 'unknown\n'
}

users_session_label() {
  case "$(users_session_kind)" in
    local) printf 'local GUI session or display manager\n' ;;
    ssh) printf 'remote SSH session\n' ;;
    headless) printf 'headless / no local GUI\n' ;;
    *) printf 'unknown session\n' ;;
  esac
}

users_ssh_connection_line() {
  [[ -n "${SSH_CONNECTION:-}" ]] || return 1
  printf '%s\n' "${SSH_CONNECTION}"
}

users_ssh_client_address() {
  [[ -n "${SSH_CONNECTION:-}" ]] || return 1
  awk '{print $1}' <<< "${SSH_CONNECTION}"
}

users_invoker_summary() {
  local user home groups
  user="$(real_user)"
  home="$(real_home)"
  groups="$(id -nG "${user}" 2>/dev/null | tr ' ' ',' || echo unknown)"
  printf '%s (%s) groups=%s effective=%s\n' \
    "${user}" "${home}" "${groups}" "$(id -un 2>/dev/null || echo unknown)"
}

users_count_login_accounts() {
  users_foreach_login_account | wc -l | tr -d ' '
}

users_count_wheel_accounts() {
  local w
  w="$(users_detect_wheel 2>/dev/null || true)"
  [[ -n "${w}" ]] || { printf '0\n'; return 0; }
  wc -w <<< "${w}" | tr -d ' '
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
