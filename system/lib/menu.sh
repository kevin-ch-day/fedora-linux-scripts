#!/usr/bin/env bash
# system/lib/menu.sh — System lane menus (host, maintenance, logs)
# Version: 0.2.2
#
# Standalone:  ./system/system.sh
# From fedora: ./fedora.sh → [1] execs ./system/system.sh
#
# Do not execute directly.

if [[ -n "${FEDORA_SYSTEM_MENU_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_SYSTEM_MENU_LOADED=1

_SYSTEM_MENU_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
_FEDORA_ROOT="$(cd -- "${_SYSTEM_MENU_LIB_DIR}/../.." && pwd)"

# shellcheck source=../../lib/health.sh
source "${_FEDORA_ROOT}/lib/health.sh"
# shellcheck source=../../lib/services.sh
source "${_FEDORA_ROOT}/lib/services.sh"
# shellcheck source=../../lib/logging.sh
source "${_FEDORA_ROOT}/lib/logging.sh"
# shellcheck source=../../lib/menu.sh
source "${_FEDORA_ROOT}/lib/menu.sh"

system_menu_header() {
  local title="$1"
  local subtitle="${2:-}"
  menu_clear_screen
  echo "${CYAN}${BOLD}${MENU_APP_NAME}${RESET}  ${DIM}$(hostname) · $(real_user)${RESET}"
  echo "Logs: $(log_dir)"
  menu_hr
  menu_print_breadcrumb
  echo "${BOLD}${title}${RESET}"
  [[ -n "${subtitle}" ]] && echo "${DIM}${subtitle}${RESET}"
}

system_menu_init() {
  local fedora_root="${1:-${_FEDORA_ROOT}}"
  menu_init "System" "${fedora_root}"
  menu_set_header_fn system_menu_header
}

# ---------- Host visibility ----------
_system_host_items() {
  menu_item 1 "System info snapshot"
  menu_item 2 "Live system monitor (Ctrl+C to exit)"
  menu_item 3 "Post-update health snapshot"
  menu_item 4 "Disk usage summary"
  menu_item 5 "Top processes (CPU)"
  menu_item_back
}

_system_host_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script_scroll system/system_info.sh; menu_pause; return 0 ;;
    2) echo "Starting live monitor..."; menu_run_script system/system_monitor.sh; return 0 ;;
    3)
      local prev="${MENU_SCROLL_MODE}"
      MENU_SCROLL_MODE=1
      health_post_update_snapshot
      MENU_SCROLL_MODE="${prev}"
      menu_pause
      return 0
      ;;
    4)
      local prev="${MENU_SCROLL_MODE}"
      MENU_SCROLL_MODE=1
      echo "Root disk:"
      health_root_disk_usage
      health_disk_top_mounts
      MENU_SCROLL_MODE="${prev}"
      menu_pause
      return 0
      ;;
    5)
      local prev="${MENU_SCROLL_MODE}"
      MENU_SCROLL_MODE=1
      health_top_processes 15
      MENU_SCROLL_MODE="${prev}"
      menu_pause
      return 0
      ;;
    *) return 2 ;;
  esac
}

system_menu_host() {
  menu_loop "Host visibility" "snapshots · monitor · disk" \
    _system_host_items _system_host_dispatch
}

# ---------- Maintenance ----------
_system_cleanup_items() {
  menu_item 1 "Truncate system_update.log"
  menu_item 2 "Truncate all .log files"
  menu_item 3 "Archive system_update.log"
  menu_item 4 "Rotate system_update.log (10 MB)"
  menu_item 5 "DNF clean (sudo)"
  menu_item_back
}

_system_cleanup_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script system/cleanup.sh --truncate-logs --quiet; menu_pause; return 0 ;;
    2) menu_run_script system/cleanup.sh --all-logs --quiet; menu_pause; return 0 ;;
    3) menu_run_script system/cleanup.sh --archive --file system_update.log --quiet; menu_pause; return 0 ;;
    4) menu_run_script system/cleanup.sh --rotate --file system_update.log --max-mb 10 --quiet; menu_pause; return 0 ;;
    5) menu_run_sudo_script system/cleanup.sh --dnf; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

_system_maint_items() {
  menu_item 1 "Full Fedora update (sudo)"
  menu_item 2 "Backup system state"
  menu_item 3 "Cleanup (logs / dnf cache)"
  menu_item 4 "Failed systemd units"
  menu_item_back
}

_system_maint_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_sudo_script system/system_update.sh; menu_pause; return 0 ;;
    2) menu_run_script system/backup_state.sh; menu_pause; return 0 ;;
    3) menu_loop "Cleanup options" "" _system_cleanup_items _system_cleanup_dispatch; return 0 ;;
    4) services_show_failed_units; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

system_menu_maintenance() {
  menu_loop "Maintenance" "update · backup · cleanup" \
    _system_maint_items _system_maint_dispatch
}

# ---------- Logs ----------
_system_logs_items() {
  menu_item 1 "Engine status"
  menu_item 2 "List logs + archive + backups"
  menu_item 3 "Summary (system_update.log)"
  menu_item 4 "Issues / errors (system_update.log)"
  menu_item 5 "Tail system_update.log (last 50)"
  menu_item 6 "Tail fedora_rebuild.log (last 50)"
  menu_item 7 "Tail mobsf.log (last 50)"
  menu_item 8 "Follow system_update.log (Ctrl+C)"
  menu_item 9 "Open logs/README"
  menu_item_back
}

_system_logs_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script_scroll system/log_engine.sh status; menu_pause; return 0 ;;
    2) menu_run_script_scroll system/log_engine.sh list; menu_pause; return 0 ;;
    3) menu_run_script_scroll system/log_engine.sh summary --file system_update.log; menu_pause; return 0 ;;
    4) menu_run_script_scroll system/log_engine.sh issues --file system_update.log --lines 80; menu_pause; return 0 ;;
    5) menu_run_script_scroll system/log_engine.sh tail --file system_update.log --lines 50; menu_pause; return 0 ;;
    6) menu_run_script_scroll system/log_engine.sh tail --file fedora_rebuild.log --lines 50; menu_pause; return 0 ;;
    7) menu_run_script_scroll system/log_engine.sh tail --file mobsf.log --lines 50; menu_pause; return 0 ;;
    8) menu_run_script_scroll system/log_engine.sh follow --file system_update.log --lines 30; return 0 ;;
    9) menu_open_file "${MENU_ROOT}/logs/README.md"; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

system_menu_logs() {
  menu_loop "Logs" "$(log_dir)" _system_logs_items _system_logs_dispatch
}

# ---------- Main system menu ----------
_system_help_items() {
  menu_item 1 "GETTING-STARTED.md"
  menu_item 2 "README.md (toolkit index)"
  menu_item 3 "CONSOLIDATION.md"
  menu_item 4 "logs/README.md"
  menu_item_back
}

_system_help_dispatch() {
  local doc=""
  case "$1" in
    0) return 1 ;;
    1) doc="${MENU_ROOT}/GETTING-STARTED.md" ;;
    2) doc="${MENU_ROOT}/README.md" ;;
    3) doc="${MENU_ROOT}/CONSOLIDATION.md" ;;
    4) doc="${MENU_ROOT}/logs/README.md" ;;
    *) return 2 ;;
  esac
  menu_open_file "${doc}"
  menu_pause
  return 0
}

system_menu_help() {
  menu_loop "Help & docs" "guides · index · logs" \
    _system_help_items _system_help_dispatch
}

_system_main_items() {
  menu_item 1 "Host visibility"
  menu_item 2 "Maintenance"
  menu_item 3 "Logs"
  menu_item 4 "Research doctor (Android + MobSF)"
  menu_item 5 "Help & docs"
  menu_item_lane_exit
}

_system_main_dispatch() {
  case "$1" in
    0) menu_lane_handle_main_exit ;;
    1) system_menu_host; return 0 ;;
    2) system_menu_maintenance; return 0 ;;
    3) system_menu_logs; return 0 ;;
    4) menu_run_script_scroll system/research_doctor.sh; menu_pause; return 0 ;;
    5) system_menu_help; return 0 ;;
    *) return 2 ;;
  esac
}

system_main_menu() {
  menu_loop "System menu" "host · maintenance · logs" \
    _system_main_items _system_main_dispatch
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
