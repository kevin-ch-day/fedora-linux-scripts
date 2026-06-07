#!/usr/bin/env bash
# lib/menu.sh — interactive TUI menu helpers for the Fedora toolkit
# Version: 0.3.2
#
# Source from launchers (fedora.sh):
#   source "${FEDORA_ROOT}/lib/menu.sh"
#   menu_init "Fedora Toolkit" "${FEDORA_ROOT}"
#
# Dispatch return codes: 0 = handled, 1 = back/exit item, 2+ = invalid choice
# At any menu prompt: r = repeat last choice (testing loops)
#
# Do not execute directly.

if [[ -n "${FEDORA_MENU_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_MENU_SH_LOADED=1

_MENU_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_MENU_LIB_DIR}/common.sh"

MENU_APP_NAME="${MENU_APP_NAME:-Fedora Toolkit}"
MENU_ROOT="${MENU_ROOT:-$(fedora_toolkit_root)}"
MENU_HEADER_FN="menu_header"
MENU_STACK=()
MENU_LAST_CHOICE=""
MENU_SCROLL_MODE=0

BOLD=""
DIM=""

menu_set_header_fn() {
  MENU_HEADER_FN="${1:?header function name required}"
}

menu_init() {
  local app_name="${1:-Fedora Toolkit}"
  local root="${2:-$(fedora_toolkit_root)}"
  MENU_APP_NAME="${app_name}"
  MENU_ROOT="${root}"
  MENU_STACK=()
  MENU_LAST_CHOICE=""
  if [[ -t 1 ]] && have tput; then
    BOLD="$(tput bold 2>/dev/null || true)"
    DIM="$(tput dim 2>/dev/null || true)"
  else
    BOLD=""
    DIM=""
  fi
}

menu_hr() {
  printf '%s\n' "--------------------------------------------------"
}

menu_breadcrumb_text() {
  local t out=""
  ((${#MENU_STACK[@]} <= 1)) && return 0
  for t in "${MENU_STACK[@]}"; do
    [[ -n "${out}" ]] && out+=" › "
    out+="${t}"
  done
  printf '%s' "${out}"
}

menu_print_breadcrumb() {
  local crumb
  crumb="$(menu_breadcrumb_text)"
  [[ -n "${crumb}" ]] && echo "${DIM}${crumb}${RESET}"
}

menu_clear_screen() {
  if (( MENU_SCROLL_MODE )); then
    echo
    echo "${DIM}── scroll mode (output kept above) ──${RESET}"
  else
    clear
  fi
}

menu_header() {
  local title="$1"
  local subtitle="${2:-}"
  menu_clear_screen
  echo "${CYAN}${BOLD}${MENU_APP_NAME}${RESET}  ${DIM}$(hostname) · $(real_user)${RESET}"
  echo "Root: ${MENU_ROOT}"
  menu_hr
  menu_print_breadcrumb
  echo "${BOLD}${title}${RESET}"
  [[ -n "${subtitle}" ]] && echo "${DIM}${subtitle}${RESET}"
}

menu_item() {
  local num="$1"
  local label="$2"
  if [[ "${num}" == "${MENU_LAST_CHOICE}" && "${num}" != "0" ]]; then
    printf '[%s] %s %s\n' "${num}" "${label}" "${DIM}← last${RESET}"
  else
    printf '[%s] %s\n' "${num}" "${label}"
  fi
}

menu_item_back() {
  menu_item 0 "Back"
}

menu_item_exit() {
  menu_item 0 "Exit"
}

menu_item_lane_exit() {
  if [[ "${FEDORA_FROM_PICKER:-}" == 1 ]]; then
    menu_item 0 "Back to lane picker"
  else
    menu_item 0 "Exit"
  fi
}

menu_lane_handle_main_exit() {
  if [[ "${FEDORA_FROM_PICKER:-}" == 1 ]]; then
    exit 0
  fi
  menu_lane_exit_msg
  exit 0
}

menu_lane_exit_msg() {
  echo "Exited. Run ./fedora.sh to pick a lane."
}

menu_print_nav_hint() {
  local hints="[0] Back"
  if [[ -n "${MENU_LAST_CHOICE}" ]]; then
    hints+="  ·  [r] Repeat last (${MENU_LAST_CHOICE})"
  fi
  echo "${DIM}${hints}${RESET}"
}

menu_read_choice() {
  local __var="${1:?variable name required}"
  local prompt="${2:-Choice: }"
  local value=""
  if ! read -r -p "${prompt}" value; then
    echo
    warn "Input closed — use [0] Back to leave this menu"
    printf -v "${__var}" '%s' ""
    return 1
  fi
  printf -v "${__var}" '%s' "${value}"
}

menu_invalid() {
  warn "Invalid choice"
  sleep 1
}

menu_pause() {
  echo
  pause_return
}

_menu_exec_script() {
  local rel="$1"
  shift
  local script="${MENU_ROOT}/${rel}"
  local rc=0
  assert_file "${script}" "Script not found: ${rel}"
  echo
  "$@" "${script}" || rc=$?
  echo
  if (( rc != 0 )); then
    warn "Action finished with errors (exit ${rc}): ${rel}"
    warn "You remain in the menu — fix the issue or pick another option."
  fi
  return 0
}

menu_run_script() {
  local rel="$1"
  shift
  _menu_exec_script "${rel}" bash "$@"
}

menu_run_sudo_script() {
  local rel="$1"
  shift
  _menu_exec_script "${rel}" sudo bash "$@"
}

menu_run_sudo_env_script() {
  local rel="$1"
  shift
  _menu_exec_script "${rel}" sudo -E bash "$@"
}

# Keep terminal output visible (doctors, verify, tail).
menu_run_script_scroll() {
  local prev="${MENU_SCROLL_MODE}"
  MENU_SCROLL_MODE=1
  menu_run_script "$@"
  MENU_SCROLL_MODE="${prev}"
}

menu_run_sudo_script_scroll() {
  local prev="${MENU_SCROLL_MODE}"
  MENU_SCROLL_MODE=1
  menu_run_sudo_script "$@"
  MENU_SCROLL_MODE="${prev}"
}

menu_run_sudo_env_script_scroll() {
  local prev="${MENU_SCROLL_MODE}"
  MENU_SCROLL_MODE=1
  menu_run_sudo_env_script "$@"
  MENU_SCROLL_MODE="${prev}"
}

menu_loop() {
  local title="$1"
  local subtitle="${2:-}"
  local render_fn="$3"
  local dispatch_fn="$4"
  local choice=""
  local rc=0

  MENU_STACK+=("${title}")

  while true; do
    "${MENU_HEADER_FN}" "${title}" "${subtitle}"
    menu_hr
    "${render_fn}"
    menu_hr
    menu_print_nav_hint
    if ! menu_read_choice choice; then
      continue
    fi
    if [[ "${choice}" == [rR] ]]; then
      if [[ -z "${MENU_LAST_CHOICE}" ]]; then
        warn "No previous choice to repeat"
        sleep 1
        continue
      fi
      choice="${MENU_LAST_CHOICE}"
      info "Repeating last choice: ${choice}"
    fi
    rc=0
    "${dispatch_fn}" "${choice}" && rc=0 || rc=$?
    case "${rc}" in
      0)
        if [[ -n "${choice}" && "${choice}" != "0" && "${choice}" != [rR] ]]; then
          MENU_LAST_CHOICE="${choice}"
        fi
        ;;
      1)
        unset 'MENU_STACK[${#MENU_STACK[@]}-1]'
        return 0
        ;;
      *) menu_invalid ;;
    esac
  done
}

menu_open_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    warn "File not found: ${path}"
    return 1
  fi
  less "${path}" 2>/dev/null || cat "${path}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
