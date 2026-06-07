#!/usr/bin/env bash
# lib/theme.sh — Fedora workstation console theme (menus + summaries)
# Version: 0.1.0
#
# Respects NO_COLOR and FEDORA_NO_COLOR=1. Call theme_init after sourcing common.sh.
# Do not execute directly.

if [[ -n "${FEDORA_THEME_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_THEME_SH_LOADED=1

THEME_USE_COLOR=0
THEME_RESET=""
THEME_BOLD=""
THEME_DIM=""
THEME_ACCENT=""
THEME_SUCCESS=""
THEME_WARN=""
THEME_ERROR=""
THEME_MUTED=""

theme_reset_vars() {
  THEME_RESET=""
  THEME_BOLD=""
  THEME_DIM=""
  THEME_ACCENT=""
  THEME_SUCCESS=""
  THEME_WARN=""
  THEME_ERROR=""
  THEME_MUTED=""
  # Backward compatibility with lib/common.sh messaging
  CYAN=""
  GREEN=""
  YELLOW=""
  RED=""
  RESET=""
  BOLD=""
  DIM=""
}

theme_use_color() {
  [[ "${THEME_USE_COLOR}" -eq 1 ]]
}

theme_init() {
  if [[ -n "${NO_COLOR:-}" || "${FEDORA_NO_COLOR:-}" == 1 ]]; then
    THEME_USE_COLOR=0
    theme_reset_vars
    return 0
  fi
  if [[ -t 1 ]] && have tput; then
    THEME_USE_COLOR=1
    THEME_RESET="$(tput sgr0 2>/dev/null || true)"
    THEME_BOLD="$(tput bold 2>/dev/null || true)"
    THEME_DIM="$(tput dim 2>/dev/null || true)"
    THEME_ACCENT="$(tput setaf 6 2>/dev/null || true)${THEME_BOLD}"
    THEME_SUCCESS="$(tput setaf 2 2>/dev/null || true)${THEME_BOLD}"
    THEME_WARN="$(tput setaf 3 2>/dev/null || true)${THEME_BOLD}"
    THEME_ERROR="$(tput setaf 1 2>/dev/null || true)${THEME_BOLD}"
    THEME_MUTED="$(tput setaf 8 2>/dev/null || true)"
    CYAN="${THEME_ACCENT}"
    GREEN="${THEME_SUCCESS}"
    YELLOW="${THEME_WARN}"
    RED="${THEME_ERROR}"
    RESET="${THEME_RESET}"
    BOLD="${THEME_BOLD}"
    DIM="${THEME_DIM}"
  else
    THEME_USE_COLOR=0
    theme_reset_vars
  fi
}

theme_rule() {
  if theme_use_color; then
    printf '%s' "${THEME_DIM}"
  fi
  printf '%.0s─' {1..52}
  printf '\n'
  if theme_use_color; then
    printf '%s' "${THEME_RESET}"
  fi
}

theme_banner() {
  local title="$1"
  echo "${THEME_ACCENT}${title}${THEME_RESET}"
}

theme_meta_line() {
  printf '%s%s%s\n' "${THEME_DIM}" "$*" "${THEME_RESET}"
}

theme_section() {
  local title="$1"
  echo
  echo "${THEME_BOLD}${title}${THEME_RESET}"
}

theme_option() {
  local num="$1"
  local label="$2"
  local hint="${3:-}"
  local last_mark=""
  if [[ -n "${MENU_LAST_CHOICE:-}" && "${num}" == "${MENU_LAST_CHOICE}" && "${num}" != "0" ]]; then
    last_mark=" ${THEME_DIM}← last${THEME_RESET}"
  fi
  if [[ -n "${hint}" ]]; then
    printf '  %s[%s]%s %s%s\n' \
      "${THEME_ACCENT}" "${num}" "${THEME_RESET}" \
      "${label}" "${last_mark}"
    printf '      %s%s%s\n' "${THEME_DIM}" "${hint}" "${THEME_RESET}"
  else
    printf '  %s[%s]%s %s%s\n' \
      "${THEME_ACCENT}" "${num}" "${THEME_RESET}" \
      "${label}" "${last_mark}"
  fi
}

theme_note() {
  printf '  %s%s%s\n' "${THEME_DIM}" "$*" "${THEME_RESET}"
}

theme_note_kv() {
  local key="$1"
  local value="$2"
  printf '  %-16s %s%s%s\n' \
    "${key}" \
    "${THEME_MUTED}${value}${THEME_RESET}"
}

theme_shortcut() {
  local key="$1"
  local value="$2"
  printf '  %s%s%s = %s%s%s\n' \
    "${THEME_DIM}" "${key}" "${THEME_RESET}" \
    "${THEME_MUTED}" "${value}" "${THEME_RESET}"
}

theme_msg_ok() {
  printf '%s[OK]%s   %s\n' "${THEME_SUCCESS}" "${THEME_RESET}" "$*"
}

theme_msg_warn() {
  printf '%s[WARN]%s %s\n' "${THEME_WARN}" "${THEME_RESET}" "$*"
}

theme_msg_err() {
  printf '%s[ERROR]%s %s\n' "${THEME_ERROR}" "${THEME_RESET}" "$*" >&2
}

theme_msg_info() {
  printf '%s[INFO]%s  %s\n' "${THEME_DIM}" "${THEME_RESET}" "$*"
}

theme_summary_box() {
  local title="$1"
  shift
  echo
  theme_rule '─'
  echo "${THEME_BOLD}${title}${THEME_RESET}"
  theme_rule '─'
  while [[ $# -gt 0 ]]; do
    printf '  %s\n' "$1"
    shift
  done
  theme_rule '─'
}

theme_choice_prompt() {
  local prompt="${1:-Choice: }"
  printf '%s%s%s' "${THEME_BOLD}" "${prompt}" "${THEME_RESET}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
