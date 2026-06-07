#!/usr/bin/env bash
# mobsf/lib/menu.sh — MobSF lane interactive menus (uses lib/menu.sh theme)
# Version: 0.1.1
#
# Standalone:  ./mobsf/mobsf.sh
# From fedora: ./fedora.sh → [4] execs ./mobsf/mobsf.sh
#
# Do not execute directly.

if [[ -n "${FEDORA_MOBSF_MENU_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_MOBSF_MENU_LOADED=1

_MOBSF_MENU_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
_FEDORA_ROOT="$(cd -- "${_MOBSF_MENU_LIB_DIR}/../.." && pwd)"

# shellcheck source=mobsf.sh
source "${_MOBSF_MENU_LIB_DIR}/mobsf.sh"
# shellcheck source=../../lib/menu.sh
source "${_FEDORA_ROOT}/lib/menu.sh"
# shellcheck source=../../lib/logging.sh
source "${_FEDORA_ROOT}/lib/logging.sh"

mobsf_menu_header() {
  local title="$1"
  local subtitle="${2:-}"
  menu_clear_screen
  echo "${CYAN}${BOLD}${MENU_APP_NAME}${RESET}  ${DIM}Podman stack · $(real_user)${RESET}"
  echo "UI: ${MOBSF_UI_URL}  ·  login: mobsf / mobsf"
  if have podman; then
    mobsf_init_paths
    echo "Compose: ${MOBSF_COMPOSE_DIR_RESOLVED}"
  else
    echo "Compose: (podman not installed)"
  fi
  menu_hr
  menu_print_breadcrumb
  echo "${BOLD}${title}${RESET}"
  [[ -n "${subtitle}" ]] && echo "${DIM}${subtitle}${RESET}"
}

mobsf_menu_init() {
  local fedora_root="${1:-${_FEDORA_ROOT}}"
  menu_init "MobSF" "${fedora_root}"
  menu_set_header_fn mobsf_menu_header
}

mobsf_menu_open_ui() {
  info "Opening ${MOBSF_UI_URL}"
  if have xdg-open; then
    xdg-open "${MOBSF_UI_URL}" >/dev/null 2>&1 &
  else
    warn "xdg-open not found — open manually: ${MOBSF_UI_URL}"
  fi
}

# ---------- Stack control ----------
_mobsf_stack_items() {
  menu_item 1 "Start stack"
  menu_item 2 "Stop stack"
  menu_item 3 "Container status"
  menu_item 4 "Open web UI in browser"
  menu_item_back
}

_mobsf_stack_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_sudo_env_script mobsf/mobsf_start.sh; menu_pause; return 0 ;;
    2) menu_run_script mobsf/mobsf_stop.sh; menu_pause; return 0 ;;
    3) menu_run_script mobsf/mobsf_status.sh; menu_pause; return 0 ;;
    4) mobsf_menu_open_ui; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

mobsf_menu_stack() {
  menu_loop "Stack control" "start · stop · status · browser" \
    _mobsf_stack_items _mobsf_stack_dispatch
}

# ---------- Setup ----------
_mobsf_setup_items() {
  menu_item 1 "Install / bootstrap (first time, sudo -E)"
  menu_item 2 "Doctor — readiness check"
  menu_item_back
}

_mobsf_setup_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_sudo_env_script mobsf/mobsf_install.sh; menu_pause; return 0 ;;
    2) menu_run_script_scroll mobsf/mobsf_doctor.sh; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

mobsf_menu_setup() {
  menu_loop "Setup" "install and verify the Podman stack" \
    _mobsf_setup_items _mobsf_setup_dispatch
}

# ---------- Maintenance ----------
_mobsf_maint_items() {
  menu_item 1 "Update images + migrate (sudo -E)"
  menu_item 2 "Reset stack — nuke data (sudo -E)"
  menu_item 3 "Reset stack — keep scan data (sudo -E)"
  menu_item 4 "Remove orphan MobSF containers"
  menu_item_back
}

_mobsf_maint_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_sudo_env_script mobsf/mobsf_update.sh; menu_pause; return 0 ;;
    2)
      warn "This removes ALL MobSF scan data and the Postgres database."
      if confirm "NUKE MobSF data and reset stack?"; then
        menu_run_sudo_env_script mobsf/mobsf_reset.sh
      else
        info "Cancelled — no changes made"
      fi
      menu_pause
      return 0
      ;;
    3)
      if confirm "Reset MobSF stack but keep scan data?"; then
        menu_run_sudo_env_script mobsf/mobsf_reset.sh --keep
      else
        info "Cancelled — no changes made"
      fi
      menu_pause
      return 0
      ;;
    4) menu_run_script mobsf/mobsf_cleanup.sh; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

mobsf_menu_maintenance() {
  menu_loop "Maintenance" "updates · reset · orphan cleanup" \
    _mobsf_maint_items _mobsf_maint_dispatch
}

# ---------- Logs ----------
_mobsf_logs_items() {
  menu_item 1 "Service logs — mobsf container (last 80 lines)"
  menu_item 2 "Ops log — tail mobsf.log (last 50)"
  menu_item 3 "Ops log — follow live (Ctrl+C to stop)"
  menu_item 4 "Ops log — errors / issues (last 80)"
  menu_item_back
}

_mobsf_logs_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script_scroll mobsf/mobsf_logs.sh mobsf --tail 80; menu_pause; return 0 ;;
    2) menu_run_script_scroll system/log_engine.sh tail --file mobsf.log --lines 50; menu_pause; return 0 ;;
    3) menu_run_script_scroll system/log_engine.sh follow --file mobsf.log --lines 30; return 0 ;;
    4) menu_run_script_scroll system/log_engine.sh issues --file mobsf.log --lines 80; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

mobsf_menu_logs() {
  menu_loop "Logs" "container output and install/reset sessions" \
    _mobsf_logs_items _mobsf_logs_dispatch
}

# ---------- Documentation ----------
_mobsf_docs_items() {
  menu_item 1 "README (overview)"
  menu_item 2 "INSTALL"
  menu_item 3 "OPERATIONS"
  menu_item 4 "STACK (architecture)"
  menu_item 5 "TROUBLESHOOTING"
  menu_item 6 "lib/ module reference"
  menu_item_back
}

_mobsf_docs_dispatch() {
  local doc=""
  case "$1" in
    0) return 1 ;;
    1) doc="${MENU_ROOT}/mobsf/README.md" ;;
    2) doc="${MENU_ROOT}/mobsf/INSTALL.md" ;;
    3) doc="${MENU_ROOT}/mobsf/OPERATIONS.md" ;;
    4) doc="${MENU_ROOT}/mobsf/STACK.md" ;;
    5) doc="${MENU_ROOT}/mobsf/TROUBLESHOOTING.md" ;;
    6) doc="${MENU_ROOT}/mobsf/lib/README.md" ;;
    *) return 2 ;;
  esac
  menu_open_file "${doc}"
  menu_pause
  return 0
}

mobsf_menu_docs() {
  menu_loop "Documentation" "" _mobsf_docs_items _mobsf_docs_dispatch
}

# ---------- Main MobSF menu ----------
_mobsf_main_items() {
  menu_item 1 "Stack control"
  menu_item 2 "Setup"
  menu_item 3 "Maintenance"
  menu_item 4 "Logs"
  menu_item 5 "Documentation"
  menu_item_lane_exit
}

_mobsf_main_dispatch() {
  case "$1" in
    0) menu_lane_handle_main_exit ;;
    1) mobsf_menu_stack; return 0 ;;
    2) mobsf_menu_setup; return 0 ;;
    3) mobsf_menu_maintenance; return 0 ;;
    4) mobsf_menu_logs; return 0 ;;
    5) mobsf_menu_docs; return 0 ;;
    *) return 2 ;;
  esac
}

mobsf_main_menu() {
  local ui="${MOBSF_UI_URL:-http://127.0.0.1:8080/}"
  menu_loop "MobSF menu" "static analysis · ${ui}" \
    _mobsf_main_items _mobsf_main_dispatch
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
