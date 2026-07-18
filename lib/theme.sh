#!/usr/bin/env bash
# lib/theme.sh — Fedora workstation console theme (dark-first, black-terminal friendly)
# Version: 0.8.0
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

# Explicit semantic aliases. The older short names remain supported throughout
# the shell UI, while these names preserve intent for future renderers.
THEME_SIGNAL=""
THEME_STATUS_SUCCESS=""
THEME_STATUS_WARNING=""
THEME_STATUS_FAILURE=""
THEME_STATUS_MUTED=""

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
  THEME_SIGNAL=""
  THEME_STATUS_SUCCESS=""
  THEME_STATUS_WARNING=""
  THEME_STATUS_FAILURE=""
  THEME_STATUS_MUTED=""
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

theme_resolved_width() {
  local configured="${THEME_WIDTH:-54}"
  local cols="${COLUMNS:-}"
  local max_width=0

  if [[ ! "${configured}" =~ ^[0-9]+$ ]] || (( configured <= 0 )); then
    configured=54
  fi

  if [[ ! "${cols}" =~ ^[0-9]+$ || "${cols}" -le 0 ]] && [[ -t 1 ]] && _theme_have tput; then
    cols="$(tput cols 2>/dev/null || true)"
  fi

  if [[ "${cols}" =~ ^[0-9]+$ ]] && (( cols > 0 )); then
    max_width=$(( cols - 4 ))
    (( max_width < 12 )) && max_width=12
    if (( configured > max_width )); then
      configured="${max_width}"
    fi
  fi

  # Keep rules inside the terminal while retaining a useful minimum on very
  # narrow displays. COLUMNS also makes width behavior testable without a TTY.
  if (( configured < 24 )); then
    if (( max_width > 0 && max_width < 24 )); then
      configured="${max_width}"
    else
      configured=24
    fi
  fi
  printf '%s\n' "${configured}"
}

theme_repeat_char() {
  local count="$1"
  local char="${2:--}"
  local i
  (( count > 0 )) || return 0
  for ((i = 0; i < count; i++)); do
    printf '%s' "${char}"
  done
}

# 256-color foreground when supported; empty otherwise.
_theme_fg256() {
  local code="$1"
  if [[ "${THEME_USE_256:-0}" -eq 1 ]]; then
    printf '\033[38;5;%sm' "${code}"
  fi
}

theme_signal_code() {
  case "${THEME_MODE}" in
    light) printf '%s' 160 ;;
    *) printf '%s' 160 ;;
  esac
}

theme_status_code() {
  local status="${1:?status required}"
  case "${THEME_MODE}:${status}" in
    light:success) printf '%s' 28 ;;
    light:warning) printf '%s' 172 ;;
    light:failure) printf '%s' 124 ;;
    dark:success|*:success) printf '%s' 82 ;;
    dark:warning|*:warning) printf '%s' 214 ;;
    dark:failure|*:failure) printf '%s' 203 ;;
    *) return 1 ;;
  esac
}

theme_lane_accent_code() {
  # Lanes are identified by labels, not a rainbow. A single signal-red accent
  # keeps the control surface coherent; green/amber/red remain status-only.
  theme_signal_code
}

theme_lane_icon() {
  case "${1:-}" in
    system) printf 'SYS / ' ;;
    install|setup) printf 'SET / ' ;;
    dev|development) printf 'DEV / ' ;;
    desktop) printf 'UI  / ' ;;
    virt|virtualization) printf 'VRT / ' ;;
    disk) printf 'DSK / ' ;;
    web) printf 'WEB / ' ;;
    host) printf 'HST / ' ;;
    android) printf 'ADR / ' ;;
    mobsf) printf 'MOB / ' ;;
    rebuild) printf 'BLD / ' ;;
    update|postupdate) printf 'UPD / ' ;;
    audit|security|readiness) printf 'AUD / ' ;;
    check|selftest) printf 'TST / ' ;;
    main|fedora) printf 'CTL / ' ;;
    profile) printf 'PRF / ' ;;
    cleanup) printf 'CLN / ' ;;
    hardening) printf 'SEC / ' ;;
    logs) printf 'LOG / ' ;;
    *) printf 'CTL / ' ;;
  esac
}

theme_lane_subtitle() {
  case "${1:-}" in
    system) printf '%s' "daily readiness · updates · logs · cleanup" ;;
    install|setup) printf '%s' "select · review · approve" ;;
    dev|development) printf '%s' "developer tools · desktops · virtualization · web stack" ;;
    android) printf '%s' "sdk · re tools · verify" ;;
    mobsf) printf '%s' "podman stack · static analysis" ;;
    rebuild) printf '%s' "guided workstation setup" ;;
    update|postupdate) printf '%s' "upgrade · maintain · verify" ;;
    audit|security) printf '%s' "readiness · compliance · findings" ;;
    main|fedora) printf '%s' "inspect · plan · apply · verify" ;;
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
    THEME_ACCENT="$(tput setaf 1 2>/dev/null || true)${THEME_BOLD}"
  fi
  THEME_SIGNAL="${THEME_ACCENT}"
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
      THEME_ACCENT="$(_theme_fg256 "$(theme_signal_code)")${THEME_BOLD}"
      THEME_TITLE="$(_theme_fg256 232)${THEME_BOLD}"
      THEME_SUCCESS="$(_theme_fg256 "$(theme_status_code success)")${THEME_BOLD}"
      THEME_WARN="$(_theme_fg256 "$(theme_status_code warning)")${THEME_BOLD}"
      THEME_ERROR="$(_theme_fg256 "$(theme_status_code failure)")${THEME_BOLD}"
      THEME_INFO="$(_theme_fg256 240)"
      ;;
    dark|*)
      THEME_FG="$(_theme_fg256 252)"
      THEME_DIM="$(_theme_fg256 245)"
      THEME_MUTED="$(_theme_fg256 240)"
      THEME_BORDER="$(_theme_fg256 238)"
      THEME_ACCENT="$(_theme_fg256 "$(theme_signal_code)")${THEME_BOLD}"
      THEME_TITLE="$(_theme_fg256 255)${THEME_BOLD}"
      THEME_SUCCESS="$(_theme_fg256 "$(theme_status_code success)")${THEME_BOLD}"
      THEME_WARN="$(_theme_fg256 "$(theme_status_code warning)")${THEME_BOLD}"
      THEME_ERROR="$(_theme_fg256 "$(theme_status_code failure)")${THEME_BOLD}"
      THEME_INFO="$(_theme_fg256 250)"
      ;;
  esac

  if [[ "${THEME_USE_256}" -eq 0 ]]; then
    THEME_DIM="$(tput dim 2>/dev/null || true)"
    THEME_MUTED="$(tput setaf 7 2>/dev/null || true)"
    THEME_BORDER="${THEME_DIM}"
    THEME_FG="${THEME_RESET}"
    THEME_ACCENT="$(tput setaf 1 2>/dev/null || true)${THEME_BOLD}"
    THEME_TITLE="$(tput setaf 15 2>/dev/null || true)${THEME_BOLD}"
    THEME_SUCCESS="$(tput setaf 10 2>/dev/null || tput setaf 2 2>/dev/null || true)${THEME_BOLD}"
    THEME_WARN="$(tput setaf 11 2>/dev/null || tput setaf 3 2>/dev/null || true)${THEME_BOLD}"
    THEME_ERROR="$(tput setaf 9 2>/dev/null || tput setaf 1 2>/dev/null || true)${THEME_BOLD}"
    THEME_INFO="$(tput setaf 7 2>/dev/null || true)"
  fi

  THEME_SIGNAL="${THEME_ACCENT}"
  THEME_STATUS_SUCCESS="${THEME_SUCCESS}"
  THEME_STATUS_WARNING="${THEME_WARN}"
  THEME_STATUS_FAILURE="${THEME_ERROR}"
  THEME_STATUS_MUTED="${THEME_MUTED}"

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
  local width="${2:-$(theme_resolved_width)}"
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
  local width
  width="$(theme_resolved_width)"
  if theme_use_color; then
    theme_rule '─' "${width}"
    echo "${THEME_TITLE}${title}${THEME_RESET}"
    theme_rule '─' "${width}"
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
  local icon sub="" width
  width="$(theme_resolved_width)"
  icon="$(theme_lane_icon "${lane}")"
  if (( $# >= 3 )); then
    sub="$3"
  else
    sub="$(theme_lane_subtitle "${lane}")"
  fi
  if theme_use_color; then
    theme_rule '═' "${width}"
    echo "${THEME_ACCENT}${icon}${THEME_RESET}${THEME_TITLE}${title}${THEME_RESET}"
    theme_rule '─' "${width}"
    [[ -n "${sub}" ]] && theme_meta_line "${sub}"
  else
    echo "${icon}${title}"
    theme_rule '─' "${width}"
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
  local width
  width="$(theme_resolved_width)"
  echo
  if theme_use_color; then
    theme_rule '═' "${width}"
    printf '%sSTEP %s%s/%s%s  %s%s%s\n' \
      "${THEME_ACCENT}" "${THEME_RESET}" "${step}" "${total}" \
      "${THEME_BOLD}" "${title}" "${THEME_RESET}"
    [[ -n "${detail}" ]] && theme_meta_line "${detail}"
    theme_rule '─' "${width}"
  else
    theme_rule '=' "${width}"
    echo "STEP [${step}/${total}]: ${title}"
    [[ -n "${detail}" ]] && echo "${detail}"
    theme_rule '=' "${width}"
  fi
}

theme_page_title() {
  local title="$1"
  if theme_use_color; then
    printf '%s[%s]%s\n' "${THEME_BOLD}${THEME_FG}" "${title}" "${THEME_RESET}"
  else
    printf '[%s]\n' "${title}"
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
  local width tail
  width="$(theme_resolved_width)"
  if [[ "${THEME_DENSITY}" == compact ]]; then
    if theme_use_color; then
      printf '  %s[%s]%s\n' "${THEME_ACCENT}" "${title}" "${THEME_RESET}"
    else
      printf '  [%s]\n' "${title}"
    fi
    return 0
  fi
  echo
  if theme_use_color; then
    printf '  %s[%s]%s' \
      "${THEME_ACCENT}" "${title}" "${THEME_RESET}"
    tail=$(( width - ${#title} - 6 ))
    if (( tail > 6 )); then
      printf ' %s' "${THEME_BORDER}"
      theme_repeat_char "${tail}" '-'
      printf '%s\n' "${THEME_RESET}"
    else
      printf '\n'
    fi
  else
    printf '  [%s] ' "${title}"
    tail=$(( width - ${#title} - 6 ))
    if (( tail > 4 )); then
      theme_repeat_char "${tail}" '-'
    fi
    printf '\n'
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
  local danger_mark=""

  icon="$(theme_lane_icon "${lane}")"
  theme_set_lane "${lane}"

  if [[ "${num}" == "0" ]]; then
    key_color="${THEME_DIM}"
  elif [[ "${style}" == danger ]]; then
    key_color="${THEME_ERROR}"
    danger_mark="DANGER / "
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
    printf '  %s[%s]%s ' "${key_color}" "${num}" "${THEME_RESET}"
    if [[ -n "${danger_mark}" ]]; then
      printf '%s%s%s' "${THEME_ERROR}" "${danger_mark}" "${THEME_RESET}"
    fi
    printf '%s%s%s%s%s%s\n' \
      "${THEME_ACCENT}" "${icon}" "${THEME_RESET}" \
      "${THEME_FG}" "${label}" "${THEME_RESET}${last_mark}"
  else
    printf '  [%s] %s%s%s%s\n' "${num}" "${danger_mark}" "${icon}" "${label}" "${last_mark}"
  fi

  if [[ -n "${hint}" ]]; then
    if theme_use_color; then
      printf '      %s↳ %s%s\n' "${THEME_DIM}" "${hint}" "${THEME_RESET}"
    else
      printf '      ↳ %s\n' "${hint}"
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
  local danger_mark=""

  if [[ "${num}" == "0" ]]; then
    key_color="${THEME_DIM}"
  elif [[ "${style}" == danger ]]; then
    key_color="${THEME_ERROR}"
    danger_mark="DANGER / "
  fi

  if [[ -n "${MENU_LAST_CHOICE:-}" && "${num}" == "${MENU_LAST_CHOICE}" && "${num}" != "0" ]]; then
    if theme_use_color; then
      last_mark=" ${THEME_DIM}← last${THEME_RESET}"
    else
      last_mark=" ← last"
    fi
  fi

  if theme_use_color; then
    printf '  %s[%s]%s ' "${key_color}" "${num}" "${THEME_RESET}"
    if [[ -n "${danger_mark}" ]]; then
      printf '%s%s%s' "${THEME_ERROR}" "${danger_mark}" "${THEME_RESET}"
    fi
    printf '%s%s%s\n' \
      "${THEME_FG}" "${label}" "${THEME_RESET}${last_mark}"
  else
    printf '  [%s] %s%s%s\n' "${num}" "${danger_mark}" "${label}" "${last_mark}"
  fi

  if [[ -n "${hint}" ]]; then
    if theme_use_color; then
      printf '      %s↳ %s%s\n' "${THEME_DIM}" "${hint}" "${THEME_RESET}"
    else
      printf '      ↳ %s\n' "${hint}"
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
    printf '  %s[%s]%s %s›%s %s%s%s\n' \
      "${THEME_ACCENT}" "${key}" "${THEME_RESET}" \
      "${THEME_BORDER}" "${THEME_RESET}" \
      "${THEME_MUTED}" "${value}" "${THEME_RESET}"
  else
    printf '  [%s] > %s\n' "${key}" "${value}"
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

theme_msg_absent() {
  if theme_use_color; then
    printf '%s[ABSENT]%s %s%s%s\n' \
      "${THEME_MUTED}" "${THEME_RESET}" \
      "${THEME_DIM}" "$*" "${THEME_RESET}"
  else
    printf '[ABSENT] %s\n' "$*"
  fi
}

theme_msg_unavail() {
  if theme_use_color; then
    printf '%s[UNAVAIL]%s %s%s%s\n' \
      "${THEME_MUTED}" "${THEME_RESET}" \
      "${THEME_DIM}" "$*" "${THEME_RESET}"
  else
    printf '[UNAVAIL] %s\n' "$*"
  fi
}

theme_msg_skip() {
  if theme_use_color; then
    printf '%s[SKIP]%s %s%s%s\n' \
      "${THEME_MUTED}" "${THEME_RESET}" \
      "${THEME_DIM}" "$*" "${THEME_RESET}"
  else
    printf '[SKIP] %s\n' "$*"
  fi
}

# Backward-compatible function name; a missing installed tool is ABSENT.
theme_msg_miss() {
  theme_msg_absent "$@"
}

theme_result_ready() {
  theme_msg_ok "${1:-READY}"
}

theme_result_issues() {
  theme_msg_warn "${1:-ISSUES — see above}"
}

theme_status_ok() {
  if theme_use_color; then
    printf '  %s[OK]%s   %s%s%s\n' \
      "${THEME_SUCCESS}" "${THEME_RESET}" \
      "${THEME_FG}" "$*" "${THEME_RESET}"
  else
    printf '  [OK]   %s\n' "$*"
  fi
}

theme_status_warn() {
  if theme_use_color; then
    printf '  %s[WARN]%s %s%s%s\n' \
      "${THEME_WARN}" "${THEME_RESET}" \
      "${THEME_FG}" "$*" "${THEME_RESET}"
  else
    printf '  [WARN] %s\n' "$*"
  fi
}

theme_status_info() {
  if theme_use_color; then
    printf '  %s[INFO]%s %s%s%s\n' \
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

# Tool/version row: status = ok | warn | err | absent | unavail | skip
theme_tool_row() {
  local status="$1"
  local label="$2"
  local detail="${3:-}"
  local tag="${label}:"
  local state_tag="" state_color="${THEME_MUTED}"

  case "${status}" in
    ok)
      state_tag="[OK]"
      state_color="${THEME_SUCCESS}"
      ;;
    warn)
      state_tag="[WARN]"
      state_color="${THEME_WARN}"
      ;;
    err)
      state_tag="[ERROR]"
      state_color="${THEME_ERROR}"
      ;;
    miss|absent)
      state_tag="[ABSENT]"
      detail="${detail:-not installed}"
      ;;
    unavail)
      state_tag="[UNAVAIL]"
      detail="${detail:-unavailable}"
      ;;
    skip)
      state_tag="[SKIP]"
      detail="${detail:-not checked}"
      ;;
    *) return 2 ;;
  esac

  if theme_use_color; then
    printf '  %s%-9s%s %s%-12s%s %s%s%s\n' \
      "${state_color}" "${state_tag}" "${THEME_RESET}" \
      "${THEME_FG}" "${tag}" "${THEME_RESET}" \
      "${THEME_DIM}" "${detail}" "${THEME_RESET}"
  else
    printf '  %-9s %-12s %s\n' "${state_tag}" "${tag}" "${detail}"
  fi
}

theme_verify_heading() {
  theme_report_section "$1"
}

theme_report_progress() {
  local step="$1"
  local total="$2"
  local title="$3"
  local pct=0 width=18 filled empty i
  if [[ "${step}" =~ ^[0-9]+$ && "${total}" =~ ^[0-9]+$ ]] && (( total > 0 )); then
    pct=$(( (step * 100) / total ))
  fi
  (( pct > 100 )) && pct=100
  filled=$(( (pct * width) / 100 ))
  empty=$(( width - filled ))

  if theme_use_color; then
    printf '%sProgress%s  %s/%s  %s' \
      "${THEME_ACCENT}" "${THEME_RESET}" "${step}" "${total}" "${THEME_SIGNAL}"
    for ((i = 0; i < filled; i++)); do printf '█'; done
    printf '%s' "${THEME_RESET}"
    for ((i = 0; i < empty; i++)); do printf '░'; done
    printf '  %3s%%\n' "${pct}"
  else
    printf 'Progress  %s/%s  ' "${step}" "${total}"
    for ((i = 0; i < filled; i++)); do printf '#'; done
    for ((i = 0; i < empty; i++)); do printf '.'; done
    printf '  %3s%%\n' "${pct}"
  fi
  theme_meta_line "ACTION / ${title}"
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
  prompt="${prompt/Choice:/Choice ›}"
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
