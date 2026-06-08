#!/usr/bin/env bash
# lib/menu.sh — interactive TUI menu helpers for the Fedora toolkit
# Version: 0.4.2
#
# Screen clear is off by default (output accumulates for dev/tuning).
# Set FEDORA_MENU_CLEAR=1 to restore full-screen redraws.
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
# shellcheck source=theme.sh
source "${_MENU_LIB_DIR}/theme.sh"

MENU_APP_NAME="${MENU_APP_NAME:-Fedora Toolkit}"
MENU_ROOT="${MENU_ROOT:-$(fedora_toolkit_root)}"
MENU_HEADER_FN="menu_header"
MENU_STACK=()
MENU_LAST_CHOICE=""
MENU_SCROLL_MODE=0
MENU_IS_ROOT=0
MENU_PARENT_CONTEXT="${MENU_PARENT_CONTEXT:-}"

menu_is_submenu() {
  ((${#MENU_STACK[@]} > 1))
}

menu_path_text() {
  local crumb
  crumb="$(menu_breadcrumb_text)"
  crumb="${crumb//Main menu/Main}"
  if [[ -n "${crumb}" ]]; then
    printf '%s\n' "${crumb}"
  elif ((${#MENU_STACK[@]} > 0)); then
    printf '%s\n' "${MENU_STACK[-1]}"
  else
    printf '%s\n' "${MENU_APP_NAME}"
  fi
}

menu_set_header_fn() {
  MENU_HEADER_FN="${1:?header function name required}"
}

menu_init() {
  local app_name="${1:-Fedora Toolkit}"
  local root="${2:-$(fedora_toolkit_root)}"
  local is_root="${3:-0}"
  MENU_APP_NAME="${app_name}"
  MENU_ROOT="${root}"
  MENU_IS_ROOT="${is_root}"
  MENU_STACK=()
  MENU_LAST_CHOICE=""
  MENU_PARENT_CONTEXT="${MENU_PARENT_CONTEXT:-}"
  theme_init
}

menu_hr() {
  theme_rule '─'
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
  if [[ -n "${crumb}" ]]; then
    theme_breadcrumb "${crumb}"
  fi
}

menu_clear_screen() {
  if [[ "${FEDORA_MENU_CLEAR:-0}" == 1 ]] && [[ -t 1 ]]; then
    clear 2>/dev/null || printf '\033[H\033[J' || true
    return 0
  fi
  if (( MENU_SCROLL_MODE )); then
    theme_scroll_marker
  fi
}

menu_header() {
  local title="$1"
  local subtitle="${2:-}"
  menu_clear_screen
  theme_lane_banner "${MENU_APP_NAME}"
  if menu_is_submenu; then
    theme_meta_line "Path: $(menu_path_text)"
  else
    theme_meta_line "Host: $(hostname) · User: $(real_user)"
    theme_meta_line "Path: ${MENU_ROOT}"
  fi
  menu_hr
  theme_page_title "${title}"
  if [[ -n "${subtitle}" ]]; then
    theme_meta_line "${subtitle}"
  fi
}

menu_item() {
  local num="$1"
  local label="$2"
  local hint="${3:-}"
  theme_option "${num}" "${label}" "${hint}"
}

menu_item_danger() {
  local num="$1"
  local label="$2"
  local hint="${3:-}"
  theme_option "${num}" "${label}" "${hint}" danger
}

menu_item_lane() {
  local num="$1"
  local lane="$2"
  local label="$3"
  local hint="${4:-}"
  theme_option_lane "${num}" "${lane}" "${label}" "${hint}"
}

menu_item_lane_danger() {
  local num="$1"
  local lane="$2"
  local label="$3"
  local hint="${4:-}"
  theme_option_lane "${num}" "${lane}" "${label}" "${hint}" danger
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
  elif [[ "${MENU_PARENT_CONTEXT:-}" == "main-menu" ]]; then
    menu_item 0 "Back"
  else
    menu_item 0 "Exit"
  fi
}

menu_lane_handle_main_exit() {
  if [[ "${FEDORA_FROM_PICKER:-}" == 1 ]]; then
    exit 0
  elif [[ "${MENU_PARENT_CONTEXT:-}" == "main-menu" ]]; then
    return 1
  fi
  menu_lane_exit_msg
  exit 0
}

menu_lane_exit_msg() {
  info "Returned to shell. Run ./fedora.sh to open the main menu."
}

menu_print_nav_hint() {
  if [[ -n "${MENU_LAST_CHOICE}" ]]; then
    theme_shortcut "r" "repeat last choice (${MENU_LAST_CHOICE})"
  fi
}

menu_read_choice() {
  local __var="${1:?variable name required}"
  local prompt="${2:-Choice: }"
  local value=""
  theme_choice_prompt "${prompt}"
  if ! read -r value; then
    echo
    info "Input closed — leaving this menu"
    printf -v "${__var}" '%s' "0"
    return 0
  fi
  printf -v "${__var}" '%s' "${value}"
}

menu_invalid() {
  warn "Invalid choice — enter a menu number, [0] to go back/exit, or r to repeat"
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

  # Optional runner prefix: sudo [-E] bash — remaining args go to the script.
  local -a runner=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      sudo|-E|bash)
        runner+=("$1")
        shift
        ;;
      *)
        break
        ;;
    esac
  done
  if ((${#runner[@]} == 0)); then
    runner=(bash)
  fi

  "${runner[@]}" "${script}" "$@" || rc=$?
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
    if [[ -z "${choice}" ]]; then
      menu_invalid
      continue
    fi
    if [[ "${choice}" == [rR] ]]; then
      if [[ -z "${MENU_LAST_CHOICE}" ]]; then
        warn "No previous choice to repeat — pick a menu number first"
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

# Shared Help & docs submenu (System, Dev, …).
# menu_help_docs_loop [lane_readme_rel] [subtitle]
# lane_readme_rel e.g. dev/README.md — optional lane guide as item 2.
menu_help_docs_loop() {
  local lane_rel="${1:-}"
  local subtitle="${2:-guides · index · logs}"

  _menu_help_docs_items() {
    menu_item 1 "docs/GETTING-STARTED.md"
    if [[ -n "${lane_rel}" ]]; then
      menu_item 2 "${lane_rel}"
      menu_item 3 "README.md (toolkit index)"
      menu_item 4 "docs/README.md (doc index)"
      menu_item 5 "logs/README.md"
    else
      menu_item 2 "README.md (toolkit index)"
      menu_item 3 "docs/README.md (doc index)"
      menu_item 4 "logs/README.md"
    fi
    menu_item_back
  }

  _menu_help_docs_dispatch() {
    local doc=""
    case "$1" in
      0) return 1 ;;
      1) doc="${MENU_ROOT}/docs/GETTING-STARTED.md" ;;
      2)
        if [[ -n "${lane_rel}" ]]; then
          doc="${MENU_ROOT}/${lane_rel}"
        else
          doc="${MENU_ROOT}/README.md"
        fi
        ;;
      3)
        if [[ -n "${lane_rel}" ]]; then
          doc="${MENU_ROOT}/README.md"
        else
          doc="${MENU_ROOT}/docs/README.md"
        fi
        ;;
      4)
        if [[ -n "${lane_rel}" ]]; then
          doc="${MENU_ROOT}/docs/README.md"
        else
          doc="${MENU_ROOT}/logs/README.md"
        fi
        ;;
      5) doc="${MENU_ROOT}/logs/README.md" ;;
      *) return 2 ;;
    esac
    menu_open_file "${doc}"
    menu_pause
    return 0
  }

  menu_loop "Help & docs" "${subtitle}" _menu_help_docs_items _menu_help_docs_dispatch
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
