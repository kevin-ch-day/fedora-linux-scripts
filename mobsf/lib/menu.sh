#!/usr/bin/env bash
# mobsf/lib/menu.sh — MobSF stack interactive menus (uses lib/menu.sh theme)
# Version: 0.2.1
#
# Entry: ./mobsf.sh (repo root) or ./mobsf/mobsf.sh
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
  theme_lane_banner "MobSF stack" mobsf
  theme_meta_line "User: $(real_user) · UI: ${MOBSF_UI_URL:-http://127.0.0.1:8080/}"
  if cmd_available podman; then
    mobsf_init_paths
    theme_meta_line "Compose: ${MOBSF_COMPOSE_DIR_RESOLVED}"
  else
    theme_meta_line "Compose: (podman not installed)"
  fi
  theme_meta_line "Login: mobsf / mobsf"
  menu_hr
  menu_print_breadcrumb
  theme_page_title "${title}"
  if [[ -n "${subtitle}" ]]; then
    theme_meta_line "${subtitle}"
  fi
}

mobsf_menu_init() {
  local fedora_root="${1:-${_FEDORA_ROOT}}"
  menu_init "MobSF" "${fedora_root}"
  theme_set_lane mobsf
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
  theme_section "Daily use"
  menu_item 1 "Start stack" "sudo -E if needed"
  menu_item 2 "Stop stack"
  menu_item 3 "Container status"
  menu_item 4 "Open web UI" "browser"
  menu_item_back
}

_mobsf_stack_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_sudo_env_script_scroll mobsf/mobsf_start.sh; menu_pause; return 0 ;;
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
  menu_item 1 "Install / bootstrap" "first time · sudo -E"
  theme_section "After install"
  theme_note_kv "Start stack" "menu [1] Stack control"
  theme_note_kv "Doctor" "./mobsf.sh --doctor"
  menu_item_back
}

_mobsf_setup_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_sudo_env_script_scroll mobsf/mobsf_install.sh; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

mobsf_menu_setup() {
  menu_loop "Setup" "first-time install and bootstrap" \
    _mobsf_setup_items _mobsf_setup_dispatch
}

# ---------- Doctor ----------
_mobsf_doctor_items() {
  menu_item 1 "Static stack readiness" "default · same as --doctor"
  menu_item 2 "Dynamic analysis" "ADB · gateway"
  menu_item 3 "Full check" "static + dynamic"
  menu_item_back
}

_mobsf_doctor_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script_scroll mobsf/mobsf_doctor.sh; menu_pause; return 0 ;;
    2) menu_run_script_scroll mobsf/mobsf_doctor.sh --dynamic-only; menu_pause; return 0 ;;
    3) menu_run_script_scroll mobsf/mobsf_doctor.sh --dynamic; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

mobsf_menu_doctor() {
  menu_loop "Doctor" "same as ./mobsf.sh --doctor" \
    _mobsf_doctor_items _mobsf_doctor_dispatch
}

# ---------- Maintenance ----------
_mobsf_maint_items() {
  theme_section "Routine"
  menu_item 1 "Update images + migrate" "sudo -E"
  menu_item 3 "Reset — keep scan data" "recommended recovery"
  menu_item 4 "Remove orphan containers"
  menu_item 5 "Login autostart" "systemd user unit"
  theme_section "Danger zone"
  menu_item_danger 2 "Reset — nuke all data" "sudo -E · destroys DB"
  menu_item_back
}

_mobsf_maint_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_sudo_env_script_scroll mobsf/mobsf_update.sh; menu_pause; return 0 ;;
    2)
      warn "This removes ALL MobSF scan data and the Postgres database."
      if confirm "NUKE MobSF data and reset stack?"; then
        menu_run_sudo_env_script_scroll mobsf/mobsf_reset.sh
      else
        info "Cancelled — no changes made"
      fi
      menu_pause
      return 0
      ;;
    3)
      if confirm "Reset MobSF stack but keep scan data?"; then
        menu_run_sudo_env_script_scroll mobsf/mobsf_reset.sh --keep
      else
        info "Cancelled — no changes made"
      fi
      menu_pause
      return 0
      ;;
    4) menu_run_script mobsf/mobsf_cleanup.sh; menu_pause; return 0 ;;
    5)
      menu_run_script mobsf/mobsf_autostart.sh status
      echo
      if confirm "Install/update MobSF login autostart unit?"; then
        menu_run_script mobsf/mobsf_autostart.sh install
      fi
      menu_pause
      return 0
      ;;
    *) return 2 ;;
  esac
}

mobsf_menu_maintenance() {
  menu_loop "Maintenance" "updates · reset · orphan cleanup" \
    _mobsf_maint_items _mobsf_maint_dispatch
}

# ---------- Logs ----------
_mobsf_logs_items() {
  theme_section "Container"
  menu_item 1 "Service logs (mobsf)" "last 80 lines"
  theme_section "Ops log (logs/mobsf.log)"
  menu_item 2 "Tail mobsf.log" "last 50"
  menu_item 3 "Follow mobsf.log" "Ctrl+C to stop"
  menu_item 4 "Errors / issues" "last 80"
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
  menu_item 1 "GUIDE (overview + install + ops)"
  menu_item 2 "STACK (architecture + lib)"
  menu_item 3 "TROUBLESHOOTING"
  menu_item_back
}

_mobsf_docs_dispatch() {
  local doc=""
  case "$1" in
    0) return 1 ;;
    1) doc="${MENU_ROOT}/mobsf/GUIDE.md" ;;
    2) doc="${MENU_ROOT}/mobsf/STACK.md" ;;
    3) doc="${MENU_ROOT}/mobsf/TROUBLESHOOTING.md" ;;
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
  theme_section "Stack"
  menu_item_lane 1 mobsf "Stack control" "start · stop · status · browser"
  menu_item_lane 2 mobsf "Setup" "first-time install (sudo -E)"
  menu_item_lane 3 mobsf "Doctor" "podman · compose · UI readiness"
  theme_section "Operations"
  menu_item_lane 4 mobsf "Maintenance" "update · reset · cleanup"
  menu_item 5 "Logs" "container · mobsf.log"
  menu_item 6 "Documentation" "guide · troubleshooting"
  theme_section "Fedora toolkit"
  theme_note_kv "Main menu" "./run.sh"
  menu_item_exit
}

_mobsf_main_dispatch() {
  case "$1" in
    0) info "MobSF menu closed. Run ./mobsf.sh to return."; exit 0 ;;
    1) mobsf_menu_stack; return 0 ;;
    2) mobsf_menu_setup; return 0 ;;
    3) mobsf_menu_doctor; return 0 ;;
    4) mobsf_menu_maintenance; return 0 ;;
    5) mobsf_menu_logs; return 0 ;;
    6) mobsf_menu_docs; return 0 ;;
    *) return 2 ;;
  esac
}

mobsf_main_menu() {
  menu_loop "MobSF menu" "separate from ./run.sh · UI http://127.0.0.1:8080/" \
    _mobsf_main_items _mobsf_main_dispatch
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
