#!/usr/bin/env bash
# lib/theme.sh — Fedora workstation console theme (dark-first, black-terminal friendly)
# Version: 0.4.2
#
# Respects NO_COLOR and FEDORA_NO_COLOR=1.
# FEDORA_THEME=dark|light (default: dark)
# FEDORA_THEME_WIDTH=54          rule width (columns)
# FEDORA_THEME_DENSITY=normal|compact
#
# Lane accents (via theme_set_lane): system · dev · android · mobsf · rebuild · audit
#
# Call theme_init once common.sh is loaded (or from theme_preview / standalone scripts).
# Do not execute directly.

if [[ -n "${FEDORA_THEME_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi

_THEME_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

_theme_have() {
  command -v "$1" >/dev/null 2>&1
}

THEME_USE_COLOR=0
THEME_MODE="${FEDORA_THEME:-dark}"
THEME_WIDTH="${FEDORA_THEME_WIDTH:-54}"
THEME_DENSITY="${FEDORA_THEME_DENSITY:-normal}"
THEME_LANE=""

THEME_RESET=""
THEME_BOLD=""
THEME_DIM=""
THEME_FG=""
THEME_ACCENT=""
THEME_TITLE=""
THEME_SUCCESS=""
THEME_WARN=""
THEME_ERROR=""
THEME_INFO=""
THEME_MUTED=""
THEME_BORDER=""

# Backward compatibility with lib/common.sh / lib/health.sh
CYAN=""
GREEN=""
YELLOW=""
RED=""
RESET=""
BOLD=""
DIM=""

theme_reset_vars() {
  THEME_RESET=""
  THEME_BOLD=""
  THEME_DIM=""
  THEME_FG=""
  THEME_ACCENT=""
  THEME_TITLE=""
  THEME_SUCCESS=""
  THEME_WARN=""
  THEME_ERROR=""
  THEME_INFO=""
  THEME_MUTED=""
  THEME_BORDER=""
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

# 256-color foreground when supported; empty otherwise.
_theme_fg256() {
  local code="$1"
  if [[ "${THEME_USE_256:-0}" -eq 1 ]]; then
    printf '\033[38;5;%sm' "${code}"
  fi
}

theme_lane_accent_code() {
  local lane="${1:-}"
  case "${lane}" in
    system) printf '%s' 75 ;;       # steel blue
    dev|development) printf '%s' 78 ;; # sea green
    android) printf '%s' 208 ;;     # orange
    mobsf) printf '%s' 141 ;;       # violet
    rebuild) printf '%s' 220 ;;     # gold
    audit|security) printf '%s' 117 ;; # sky
    main|fedora) printf '%s' 86 ;;  # cyan
    *) printf '%s' 86 ;;
  esac
}

theme_lane_icon() {
  case "${1:-}" in
    system) printf '⚙ ' ;;
    dev|development) printf '⚡ ' ;;
    android) printf '◈ ' ;;
    mobsf) printf '⬡ ' ;;
    rebuild) printf '↻ ' ;;
    audit|security) printf '◉ ' ;;
    main|fedora) printf '◆ ' ;;
    *) printf '· ' ;;
  esac
}

theme_lane_subtitle() {
  case "${1:-}" in
    system) printf '%s' "host · updates · logs · hardening" ;;
    dev|development) printf '%s' "git · vscode · kvm · lamp" ;;
    android) printf '%s' "sdk · re tools · verify" ;;
    mobsf) printf '%s' "podman stack · static analysis" ;;
    rebuild) printf '%s' "guided workstation setup" ;;
    audit|security) printf '%s' "readiness · compliance · findings" ;;
    main|fedora) printf '%s' "fedora workstation toolkit" ;;
    *) printf '%s' "" ;;
  esac
}

theme_set_lane() {
  local lane="${1:-}"
  local code
  THEME_LANE="${lane}"
  [[ "${THEME_USE_COLOR}" -eq 1 ]] || return 0
  code="$(theme_lane_accent_code "${lane}")"
  if [[ "${THEME_USE_256:-0}" -eq 1 ]]; then
    THEME_ACCENT="$(_theme_fg256 "${code}")${THEME_BOLD}"
  else
    case "${lane}" in
      system) THEME_ACCENT="$(tput setaf 4 2>/dev/null || true)${THEME_BOLD}" ;;
      dev|development) THEME_ACCENT="$(tput setaf 2 2>/dev/null || true)${THEME_BOLD}" ;;
      android) THEME_ACCENT="$(tput setaf 3 2>/dev/null || true)${THEME_BOLD}" ;;
      mobsf) THEME_ACCENT="$(tput setaf 5 2>/dev/null || true)${THEME_BOLD}" ;;
      *) THEME_ACCENT="$(tput setaf 6 2>/dev/null || true)${THEME_BOLD}" ;;
    esac
  fi
  CYAN="${THEME_ACCENT}"
}

theme_init() {
  local tcolors=0

  if [[ -n "${NO_COLOR:-}" || "${FEDORA_NO_COLOR:-}" == 1 ]]; then
    THEME_USE_COLOR=0
    theme_reset_vars
    return 0
  fi

  if [[ ! -t 1 ]] || ! _theme_have tput; then
    THEME_USE_COLOR=0
    theme_reset_vars
    return 0
  fi

  tcolors="$(tput colors 2>/dev/null || echo 0)"
  THEME_USE_256=0
  if [[ "${tcolors}" =~ ^[0-9]+$ ]] && (( tcolors >= 256 )); then
    THEME_USE_256=1
  fi

  THEME_USE_COLOR=1
  THEME_RESET="$(tput sgr0 2>/dev/null || true)"
  THEME_BOLD="$(tput bold 2>/dev/null || true)"

  case "${THEME_MODE}" in
    light)
      THEME_FG="$(_theme_fg256 236)"
      THEME_DIM="$(_theme_fg256 240)"
      THEME_MUTED="$(_theme_fg256 245)"
      THEME_BORDER="$(_theme_fg256 250)"
      THEME_ACCENT="$(_theme_fg256 32)${THEME_BOLD}"
      THEME_TITLE="$(_theme_fg256 25)${THEME_BOLD}"
      THEME_SUCCESS="$(_theme_fg256 28)${THEME_BOLD}"
      THEME_WARN="$(_theme_fg256 172)${THEME_BOLD}"
      THEME_ERROR="$(_theme_fg256 160)${THEME_BOLD}"
      THEME_INFO="$(_theme_fg256 32)"
      ;;
    dark|*)
      THEME_FG="$(_theme_fg256 252)"
      THEME_DIM="$(_theme_fg256 245)"
      THEME_MUTED="$(_theme_fg256 240)"
      THEME_BORDER="$(_theme_fg256 238)"
      THEME_ACCENT="$(_theme_fg256 86)${THEME_BOLD}"
      THEME_TITLE="$(_theme_fg256 255)${THEME_BOLD}"
      THEME_SUCCESS="$(_theme_fg256 82)${THEME_BOLD}"
      THEME_WARN="$(_theme_fg256 214)${THEME_BOLD}"
      THEME_ERROR="$(_theme_fg256 203)${THEME_BOLD}"
      THEME_INFO="$(_theme_fg256 117)"
      ;;
  esac

  if [[ "${THEME_USE_256}" -eq 0 ]]; then
    THEME_DIM="$(tput dim 2>/dev/null || true)"
    THEME_MUTED="$(tput setaf 7 2>/dev/null || true)"
    THEME_BORDER="${THEME_DIM}"
    THEME_FG="${THEME_RESET}"
    THEME_ACCENT="$(tput setaf 14 2>/dev/null || tput setaf 6 2>/dev/null || true)${THEME_BOLD}"
    THEME_TITLE="$(tput setaf 15 2>/dev/null || true)${THEME_BOLD}"
    THEME_SUCCESS="$(tput setaf 10 2>/dev/null || tput setaf 2 2>/dev/null || true)${THEME_BOLD}"
    THEME_WARN="$(tput setaf 11 2>/dev/null || tput setaf 3 2>/dev/null || true)${THEME_BOLD}"
    THEME_ERROR="$(tput setaf 9 2>/dev/null || tput setaf 1 2>/dev/null || true)${THEME_BOLD}"
    THEME_INFO="$(tput setaf 12 2>/dev/null || tput setaf 6 2>/dev/null || true)"
  fi

  CYAN="${THEME_ACCENT}"
  GREEN="${THEME_SUCCESS}"
  YELLOW="${THEME_WARN}"
  RED="${THEME_ERROR}"
  RESET="${THEME_RESET}"
  BOLD="${THEME_BOLD}"
  DIM="${THEME_DIM}"

  if [[ -n "${THEME_LANE}" ]]; then
    theme_set_lane "${THEME_LANE}"
  fi
}

theme_rule() {
  local char="${1:-─}"
  local width="${2:-${THEME_WIDTH}}"
  local i
  if theme_use_color; then
    printf '%s' "${THEME_BORDER}"
  fi
  for ((i = 0; i < width; i++)); do
    printf '%s' "${char}"
  done
  printf '\n'
  if theme_use_color; then
    printf '%s' "${THEME_RESET}"
  fi
}

theme_plain_banner() {
  local title="$1"
  if theme_use_color; then
    echo "${THEME_TITLE}${title}${THEME_RESET}"
    theme_rule '─'
  else
    echo "${title}"
    theme_rule '─'
  fi
}

# Default banner (no lane icon) — reports, doctors, validation.
theme_banner() {
  theme_plain_banner "$1"
}

# Lane-branded banner (icon + accent from theme_set_lane).
theme_lane_banner() {
  local title="$1"
  local lane="${2:-${THEME_LANE:-main}}"
  local icon sub=""
  icon="$(theme_lane_icon "${lane}")"
  sub="$(theme_lane_subtitle "${lane}")"
  if theme_use_color; then
    echo "${THEME_ACCENT}${icon}${THEME_RESET}${THEME_TITLE}${title}${THEME_RESET}"
    theme_rule '─'
    [[ -n "${sub}" ]] && theme_meta_line "${sub}"
  else
    theme_plain_banner "${title}"
    [[ -n "${sub}" ]] && theme_meta_line "${sub}"
  fi
}

theme_report_header() {
  local title="$1"
  shift
  theme_plain_banner "${title}"
  while [[ $# -gt 0 ]]; do
    theme_meta_line "$1"
    shift
  done
  echo
}

theme_report_section() {
  local title="$1"
  if [[ "${THEME_DENSITY}" == compact ]]; then
    theme_section "${title}"
    return 0
  fi
  echo
  theme_rule '─'
  if theme_use_color; then
    printf ' %s%s%s\n' "${THEME_BOLD}${THEME_FG}" "${title}" "${THEME_RESET}"
  else
    printf ' %s\n' "${title}"
  fi
}

theme_report_step() {
  local step="$1"
  local total="$2"
  local title="$3"
  local detail="${4:-}"
  echo
  if theme_use_color; then
    theme_rule '═'
    printf '%sSTEP %s%s/%s%s  %s%s%s\n' \
      "${THEME_ACCENT}" "${THEME_RESET}" "${step}" "${total}" \
      "${THEME_BOLD}" "${title}" "${THEME_RESET}"
    [[ -n "${detail}" ]] && theme_meta_line "${detail}"
    theme_rule '─'
  else
    echo "============================================================"
    echo "STEP [${step}/${total}]: ${title}"
    [[ -n "${detail}" ]] && echo "${detail}"
    echo "============================================================"
  fi
}

theme_page_title() {
  if theme_use_color; then
    echo "${THEME_BOLD}${THEME_FG}${1}${THEME_RESET}"
  else
    echo "${1}"
  fi
}

theme_meta_line() {
  if theme_use_color; then
    printf '%s%s%s\n' "${THEME_MUTED}" "$*" "${THEME_RESET}"
  else
    printf '%s\n' "$*"
  fi
}

theme_breadcrumb() {
  local text="$1"
  local rest="${text}" seg first=1
  if ! theme_use_color; then
    printf '%s\n' "${text}"
    return 0
  fi
  while [[ "${rest}" == *" › "* ]]; do
    seg="${rest%% › *}"
    rest="${rest#* › }"
    if (( first )); then
      printf '%s%s%s' "${THEME_DIM}" "${seg}" "${THEME_RESET}"
      first=0
    else
      printf '%s › %s%s%s' "${THEME_DIM}" "${seg}" "${THEME_RESET}"
    fi
  done
  if (( first )); then
    printf '%s%s%s\n' "${THEME_ACCENT}" "${rest}" "${THEME_RESET}"
  else
    printf '%s › %s%s%s\n' "${THEME_DIM}" "${THEME_ACCENT}" "${rest}" "${THEME_RESET}"
  fi
}

theme_scroll_marker() {
  local msg="${1:-scroll mode — output kept above}"
  echo
  if theme_use_color; then
    printf '%s  · %s%s%s ·\n' \
      "${THEME_BORDER}" "${THEME_DIM}" "${msg}" "${THEME_RESET}"
  else
    printf '── %s ──\n' "${msg}"
  fi
}

theme_section() {
  local title="$1"
  if [[ "${THEME_DENSITY}" == compact ]]; then
    if theme_use_color; then
      printf '  %s▸%s %s\n' "${THEME_ACCENT}" "${THEME_RESET}" "${title}"
    else
      printf '  ▸ %s\n' "${title}"
    fi
    return 0
  fi
  echo
  if theme_use_color; then
    printf '  %s▸%s %s%s%s\n' \
      "${THEME_ACCENT}" "${THEME_RESET}" \
      "${THEME_BOLD}" "${title}" "${THEME_RESET}"
  else
    printf '  ▸ %s\n' "${title}"
  fi
}

theme_kv() {
  local key="$1"
  local value="$2"
  local width="${3:-14}"
  if theme_use_color; then
    printf '  %s%-*s%s %s%s%s\n' \
      "${THEME_DIM}" "${width}" "${key}" "${THEME_RESET}" \
      "${THEME_FG}" "${value}" "${THEME_RESET}"
  else
    printf '  %-*s : %s\n' "${width}" "${key}" "${value}"
  fi
}

theme_option_lane() {
  local num="$1"
  local lane="$2"
  local label="$3"
  local hint="${4:-}"
  local style="${5:-}"
  local icon key_color="${THEME_ACCENT}"
  local saved_lane="${THEME_LANE:-}"
  local last_mark=""

  icon="$(theme_lane_icon "${lane}")"
  theme_set_lane "${lane}"

  if [[ "${num}" == "0" ]]; then
    key_color="${THEME_DIM}"
  elif [[ "${style}" == danger ]]; then
    key_color="${THEME_ERROR}"
  elif theme_use_color && [[ "${THEME_USE_256:-0}" -eq 1 ]]; then
    key_color="$(_theme_fg256 "$(theme_lane_accent_code "${lane}")")${THEME_BOLD}"
  fi

  if [[ -n "${MENU_LAST_CHOICE:-}" && "${num}" == "${MENU_LAST_CHOICE}" && "${num}" != "0" ]]; then
    if theme_use_color; then
      last_mark=" ${THEME_DIM}← last${THEME_RESET}"
    else
      last_mark=" ← last"
    fi
  fi

  if theme_use_color; then
    printf '  %s[%s]%s %s%s%s%s\n' \
      "${key_color}" "${num}" "${THEME_RESET}" \
      "${THEME_ACCENT}" "${icon}" "${THEME_FG}" "${label}${THEME_RESET}${last_mark}"
  else
    printf '  [%s] %s%s%s\n' "${num}" "${icon}" "${label}" "${last_mark}"
  fi

  if [[ -n "${hint}" ]]; then
    if theme_use_color; then
      printf '      %s%s%s\n' "${THEME_DIM}" "${hint}" "${THEME_RESET}"
    else
      printf '      %s\n' "${hint}"
    fi
  fi

  if [[ -n "${saved_lane}" ]]; then
    theme_set_lane "${saved_lane}"
  fi
}

theme_option() {
  local num="$1"
  local label="$2"
  local hint="${3:-}"
  local style="${4:-}"
  local last_mark=""
  local key_color="${THEME_ACCENT}"

  if [[ "${num}" == "0" ]]; then
    key_color="${THEME_DIM}"
  elif [[ "${style}" == danger ]]; then
    key_color="${THEME_ERROR}"
  fi

  if [[ -n "${MENU_LAST_CHOICE:-}" && "${num}" == "${MENU_LAST_CHOICE}" && "${num}" != "0" ]]; then
    if theme_use_color; then
      last_mark=" ${THEME_DIM}← last${THEME_RESET}"
    else
      last_mark=" ← last"
    fi
  fi

  if theme_use_color; then
    printf '  %s[%s]%s %s%s%s\n' \
      "${key_color}" "${num}" "${THEME_RESET}" \
      "${THEME_FG}" "${label}" "${THEME_RESET}${last_mark}"
  else
    printf '  [%s] %s%s\n' "${num}" "${label}" "${last_mark}"
  fi

  if [[ -n "${hint}" ]]; then
    if theme_use_color; then
      printf '      %s%s%s\n' "${THEME_DIM}" "${hint}" "${THEME_RESET}"
    else
      printf '      %s\n' "${hint}"
    fi
  fi
}

theme_note() {
  if theme_use_color; then
    printf '  %s%s%s\n' "${THEME_DIM}" "$*" "${THEME_RESET}"
  else
    printf '  %s\n' "$*"
  fi
}

theme_note_kv() {
  local key="$1"
  local value="$2"
  if theme_use_color; then
    printf '  %s%-16s%s %s%s%s\n' \
      "${THEME_DIM}" "${key}" "${THEME_RESET}" \
      "${THEME_MUTED}" "${value}" "${THEME_RESET}"
  else
    printf '  %-16s %s\n' "${key}" "${value}"
  fi
}

theme_shortcut() {
  local key="$1"
  local value="$2"
  if theme_use_color; then
    printf '  %s%s%s = %s%s%s\n' \
      "${THEME_ACCENT}" "${key}" "${THEME_RESET}" \
      "${THEME_DIM}" "${value}" "${THEME_RESET}"
  else
    printf '  %s = %s\n' "${key}" "${value}"
  fi
}

theme_msg_ok() {
  if theme_use_color; then
    printf '%s[OK]%s   %s%s%s\n' \
      "${THEME_SUCCESS}" "${THEME_RESET}" \
      "${THEME_FG}" "$*" "${THEME_RESET}"
  else
    printf '[OK]   %s\n' "$*"
  fi
}

theme_msg_warn() {
  if theme_use_color; then
    printf '%s[WARN]%s %s%s%s\n' \
      "${THEME_WARN}" "${THEME_RESET}" \
      "${THEME_FG}" "$*" "${THEME_RESET}"
  else
    printf '[WARN] %s\n' "$*"
  fi
}

theme_msg_err() {
  if theme_use_color; then
    printf '%s[ERROR]%s %s%s%s\n' \
      "${THEME_ERROR}" "${THEME_RESET}" \
      "${THEME_FG}" "$*" "${THEME_RESET}" >&2
  else
    printf '[ERROR] %s\n' "$*" >&2
  fi
}

theme_msg_info() {
  if theme_use_color; then
    printf '%s[INFO]%s  %s%s%s\n' \
      "${THEME_INFO}" "${THEME_RESET}" \
      "${THEME_DIM}" "$*" "${THEME_RESET}"
  else
    printf '[INFO] %s\n' "$*"
  fi
}

theme_msg_miss() {
  if theme_use_color; then
    printf '%s[MISS]%s %s%s%s\n' \
      "${THEME_MUTED}" "${THEME_RESET}" \
      "${THEME_DIM}" "$*" "${THEME_RESET}"
  else
    printf '[MISS] %s\n' "$*"
  fi
}

theme_result_ready() {
  theme_msg_ok "${1:-READY}"
}

theme_result_issues() {
  theme_msg_warn "${1:-ISSUES — see above}"
}

theme_status_ok() {
  if theme_use_color; then
    printf '  %s✓%s %s%s%s\n' \
      "${THEME_SUCCESS}" "${THEME_RESET}" \
      "${THEME_FG}" "$*" "${THEME_RESET}"
  else
    printf '  [OK]   %s\n' "$*"
  fi
}

theme_status_warn() {
  if theme_use_color; then
    printf '  %s!%s %s%s%s\n' \
      "${THEME_WARN}" "${THEME_RESET}" \
      "${THEME_FG}" "$*" "${THEME_RESET}"
  else
    printf '  [WARN] %s\n' "$*"
  fi
}

theme_status_info() {
  if theme_use_color; then
    printf '  %s·%s %s%s%s\n' \
      "${THEME_INFO}" "${THEME_RESET}" \
      "${THEME_DIM}" "$*" "${THEME_RESET}"
  else
    printf '  [INFO] %s\n' "$*"
  fi
}

theme_gauge_bar() {
  local pct="${1:-0}" width="${2:-18}"
  local filled empty i color="${THEME_SUCCESS}"

  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100
  filled=$(( (pct * width) / 100 ))
  empty=$(( width - filled ))

  if (( pct >= 85 )); then
    color="${THEME_ERROR}"
  elif (( pct >= 70 )); then
    color="${THEME_WARN}"
  fi

  if theme_use_color; then
    printf '%s' "${color}"
  fi
  for ((i = 0; i < filled; i++)); do printf '█'; done
  if theme_use_color; then
    printf '%s' "${THEME_RESET}"
  fi
  for ((i = 0; i < empty; i++)); do printf '░'; done
}

# Tool/version row: status = ok | warn | err | miss | skip
theme_tool_row() {
  local status="$1"
  local label="$2"
  local detail="${3:-}"
  local tag="${label}:"

  case "${status}" in
    ok)
      if theme_use_color; then
        printf '  %s[OK]%s   %s%-12s%s %s%s%s\n' \
          "${THEME_SUCCESS}" "${THEME_RESET}" \
          "${THEME_FG}" "${tag}" "${THEME_RESET}" \
          "${THEME_DIM}" "${detail}" "${THEME_RESET}"
      else
        printf '  [OK]   %-12s %s\n' "${tag}" "${detail}"
      fi
      ;;
    warn)
      if theme_use_color; then
        printf '  %s[WARN]%s %s%-12s%s %s%s%s\n' \
          "${THEME_WARN}" "${THEME_RESET}" \
          "${THEME_FG}" "${tag}" "${THEME_RESET}" \
          "${THEME_DIM}" "${detail}" "${THEME_RESET}"
      else
        printf '  [WARN] %-12s %s\n' "${tag}" "${detail}"
      fi
      ;;
    err)
      if theme_use_color; then
        printf '  %s[ERR]%s  %s%-12s%s %s%s%s\n' \
          "${THEME_ERROR}" "${THEME_RESET}" \
          "${THEME_FG}" "${tag}" "${THEME_RESET}" \
          "${THEME_DIM}" "${detail}" "${THEME_RESET}" >&2
      else
        printf '  [ERROR] %-12s %s\n' "${tag}" "${detail}" >&2
      fi
      ;;
    miss|skip)
      if theme_use_color; then
        printf '  %s[--]%s  %s%-12s%s %s%s%s\n' \
          "${THEME_MUTED}" "${THEME_RESET}" \
          "${THEME_DIM}" "${tag}" "${THEME_RESET}" \
          "${THEME_MUTED}" "${detail:-not installed}" "${THEME_RESET}"
      else
        printf '  [--]   %-12s %s\n' "${tag}" "${detail:-not installed}"
      fi
      ;;
  esac
}

theme_verify_heading() {
  theme_report_section "$1"
}

theme_report_progress() {
  local step="$1"
  local total="$2"
  local title="$3"
  if theme_use_color; then
    printf '%s▸%s Step %s/%s  %s%s%s\n' \
      "${THEME_ACCENT}" "${THEME_RESET}" \
      "${step}" "${total}" \
      "${THEME_BOLD}" "${title}" "${THEME_RESET}"
  else
    printf 'Step %s/%s — %s\n' "${step}" "${total}" "${title}"
  fi
}

_theme_summary_value_color() {
  local value="$1"
  case "${value}" in
    *NOT\ READY*|*FAILED*|*failed*)
      printf '%s' "${THEME_ERROR}"
      ;;
    *READY*|*PASSED*|*passed*|*ready*)
      printf '%s' "${THEME_SUCCESS}"
      ;;
    *WARN*|*warn*|*ISSUES*)
      printf '%s' "${THEME_WARN}"
      ;;
    *)
      if theme_use_color; then
        printf '%s' "${THEME_FG}"
      fi
      ;;
  esac
}

theme_summary_row() {
  local key="$1"
  local value="$2"
  local width="${3:-11}"
  if theme_use_color; then
    printf '  %s%-*s%s %s%s%s\n' \
      "${THEME_DIM}" "${width}" "${key}" "${THEME_RESET}" \
      "$(_theme_summary_value_color "${value}")${value}${THEME_RESET}"
  else
    printf '  %-*s %s\n' "${width}" "${key}" "${value}"
  fi
}

theme_summary_box() {
  local title="$1"
  shift
  echo
  theme_rule '─'
  if theme_use_color; then
    echo "${THEME_BOLD}${THEME_FG}${title}${THEME_RESET}"
  else
    echo "${title}"
  fi
  theme_rule '─'
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == *:* ]]; then
      local key="${1%%:*}"
      local rest="${1#*:}"
      rest="${rest# }"
      theme_summary_row "${key}:" "${rest}"
    elif theme_use_color; then
      printf '  %s%s%s\n' "${THEME_FG}" "$1" "${THEME_RESET}"
    else
      printf '  %s\n' "$1"
    fi
    shift
  done
  theme_rule '─'
}

theme_fail_list() {
  local item
  for item in "$@"; do
    if theme_use_color; then
      printf '  %s·%s %s%s%s\n' \
        "${THEME_ERROR}" "${THEME_RESET}" \
        "${THEME_DIM}" "${item}" "${THEME_RESET}"
    else
      printf '  · %s\n' "${item}"
    fi
  done
}

theme_choice_prompt() {
  local prompt="${1:-Choice: }"
  if theme_use_color; then
    printf '%s%s%s' "${THEME_ACCENT}" "${prompt}" "${THEME_RESET}"
  else
    printf '%s' "${prompt}"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  printf '[ERROR] Source this file; do not execute directly.\n' >&2
  exit 1
fi

FEDORA_THEME_SH_LOADED=1
