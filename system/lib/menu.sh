#!/usr/bin/env bash
# system/lib/menu.sh — System maintenance menus (host, maintenance, logs)
# Version: 0.3.1
#
# Standalone:  ./system/system.sh
# From main:   ./fedora.sh → [1] or ./fedora.sh --system
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
# shellcheck source=../../lib/health_snapshot.sh
source "${_FEDORA_ROOT}/lib/health_snapshot.sh"
# shellcheck source=../../lib/menu.sh
source "${_FEDORA_ROOT}/lib/menu.sh"

system_menu_header() {
  local title="$1"
  local subtitle="${2:-}"
  menu_clear_screen
  theme_lane_banner "System maintenance" system
  if menu_is_submenu; then
    theme_meta_line "Path: $(menu_path_text)"
  else
    theme_meta_line "Host: $(hostname) · User: $(real_user) · logs: $(log_dir)"
  fi
  menu_hr
  theme_page_title "${title}"
  if [[ -n "${subtitle}" ]]; then
    theme_meta_line "${subtitle}"
  fi
}

system_menu_maintenance_header() {
  local title="$1"
  local subtitle="${2:-}"
  menu_clear_screen
  theme_rule '═'
  if theme_use_color; then
    printf '%s⚙ System maintenance%s\n' "${THEME_TITLE}" "${THEME_RESET}"
  else
    printf '⚙ System maintenance\n'
  fi
  theme_meta_line "inspect and maintain the Fedora host"
  theme_meta_line "Path: $(menu_path_text)"
  menu_hr
  theme_page_title "${title}"
  if [[ -n "${subtitle}" ]]; then
    theme_meta_line "${subtitle}"
  fi
}

system_menu_init() {
  local fedora_root="${1:-${_FEDORA_ROOT}}"
  menu_init "System maintenance" "${fedora_root}" 0
  theme_set_lane system
  menu_set_header_fn system_menu_header
}

# ---------- Cleanup submenu ----------
_system_cleanup_items() {
  theme_section "Log files"
  menu_item 1 "Truncate system_update.log"
  menu_item 2 "Truncate all .log files"
  menu_item 3 "Archive system_update.log"
  menu_item 4 "Rotate system_update.log" "10 MB max"
  theme_section "System"
  menu_item 5 "DNF clean" "sudo"
  menu_item 6 "Fix DNF repo permissions" "sudo · rebuild-check fix"
  menu_item 7 "Failed systemd units"
  menu_item_back
}

_system_cleanup_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script system/cleanup.sh --truncate-logs --quiet; menu_pause; return 0 ;;
    2) menu_run_script system/cleanup.sh --all-logs --quiet; menu_pause; return 0 ;;
    3) menu_run_script system/cleanup.sh --archive --file system_update.log --quiet; menu_pause; return 0 ;;
    4) menu_run_script system/cleanup.sh --rotate --file system_update.log --max-mb 10 --quiet; menu_pause; return 0 ;;
    5) menu_run_sudo_script_scroll system/cleanup.sh --dnf; menu_pause; return 0 ;;
    6) menu_run_sudo_script_scroll system/fix_dnf_repo_permissions.sh; menu_pause; return 0 ;;
    7) services_show_failed_units; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

system_menu_cleanup() {
  menu_loop "Cleanup" "logs · dnf · repo permissions" \
    _system_cleanup_items _system_cleanup_dispatch
}

# ---------- Disk and memory submenu ----------
_system_disk_memory_items() {
  theme_section "Disk and memory"
  menu_item 1 "Show quick disk/memory summary" "RAM · swap · filesystems · cleanup targets"
  menu_item 2 "Refresh health snapshot" "update stored health state"
  menu_item 3 "Export full diagnostic report" "verbose report saved to file"
  menu_item_back
}

_system_disk_memory_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script_scroll system/health_snapshot.sh --show; menu_pause; return 0 ;;
    2) menu_run_script_scroll system/health_snapshot.sh --refresh; menu_pause; return 0 ;;
    3) menu_run_script_scroll system/health_snapshot.sh --export; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

system_menu_disk_memory() {
  menu_loop "Disk and memory" "snapshot · dashboard · export" \
    _system_disk_memory_items _system_disk_memory_dispatch
}

# ---------- Workstation readiness submenu ----------
_system_readiness_items() {
  theme_section "Daily driver"
  menu_item 1 "Daily driver check" "read-only · boot · btrfs · LUKS · vbox"
  theme_section "Stabilization"
  menu_item 2 "Btrfs health" "device stats · scrub status"
  menu_item 3 "LUKS readiness" "keyslots (sudo) · header backups"
  menu_item 4 "VirtualBox readiness" "modules · vboxdrv · packages"
  menu_item 5 "Package / update noise" "PackageKit · dnf · flatpak"
  menu_item 6 "Post-update check" "after dnf upgrade"
  theme_section "Recovery"
  menu_item 7 "Backup current state" "export for reinstall"
  menu_item 8 "Host context snapshot" "users · network · posture"
  menu_item_back
}

_system_readiness_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script_scroll system/daily_driver_check.sh; menu_pause; return 0 ;;
    2) menu_run_script_scroll system/btrfs_health.sh; menu_pause; return 0 ;;
    3) menu_run_script_scroll system/luks_readiness.sh; menu_pause; return 0 ;;
    4) menu_run_script_scroll system/virtualbox_readiness.sh; menu_pause; return 0 ;;
    5) menu_run_script_scroll system/package_noise.sh; menu_pause; return 0 ;;
    6) menu_run_script_scroll system/post_update_check.sh; menu_pause; return 0 ;;
    7) menu_run_script_scroll system/backup_state.sh; menu_pause; return 0 ;;
    8) menu_run_script_scroll system/host_context.sh --summary; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

system_menu_readiness() {
  menu_loop "Workstation readiness" "daily driver · stabilization · recovery" \
    _system_readiness_items _system_readiness_dispatch
}

# ---------- OS hardening submenu ----------
_system_hardening_items() {
  theme_section "Round 1 — safe baseline"
  menu_item 1 "OS hardening Round 1" "sudo · auto-detect · idempotent"
  menu_item 4 "Round 1 status" "read-only · what's applied"
  theme_section "Round 2 — strict profile"
  menu_item_danger 5 "OS hardening Round 2" "sudo · firewall + services"
  menu_item_danger 7 "Strict firewall (SSH only)" "custom zone · wired NM"
  menu_item_danger 8 "Listening hardening" "MariaDB · Avahi · LLMNR · BT/Wi-Fi"
  menu_item_danger 6 "Wired only (BT/Wi-Fi off)" "wired Ethernet · mask BT"
  theme_section "Audit"
  menu_item 9 "Security audit" "read-only · findings · full report"
  menu_item 10 "Audit summary" "fast · live findings only"
  menu_item 11 "Audit action plan" "ordered remediation steps"
  menu_item 12 "Host context" "users · network · posture snapshot"
  theme_section "Round 2 prep"
  menu_item 2 "Services audit" "profile-aware · read-only"
  menu_item 3 "Help" "hardening notes"
  menu_item_back
}

_system_hardening_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script_scroll system/hardening_round1.sh; menu_pause; return 0 ;;
    5) menu_run_script_scroll system/hardening_round2.sh; menu_pause; return 0 ;;
    6) menu_run_script_scroll system/hardening_wired_only.sh; menu_pause; return 0 ;;
    7) menu_run_script_scroll system/hardening_firewall_strict.sh; menu_pause; return 0 ;;
    8) menu_run_script_scroll system/hardening_listening.sh; menu_pause; return 0 ;;
    9) menu_run_script_scroll system/security_audit.sh; return 0 ;;
    10) menu_run_script_scroll system/security_audit.sh --summary; return 0 ;;
    11) menu_run_script_scroll system/security_audit.sh --plan; return 0 ;;
    12) menu_run_script_scroll system/host_context.sh --summary; return 0 ;;
    2) menu_run_script_scroll system/hardening_services_audit.sh; menu_pause; return 0 ;;
    3)
      cat <<EOF

OS hardening
────────────
Round 1: baseline, SELinux, SSH, sysctl, journald, firewalld.
  Host/OS/profile/users detected automatically.
  Idempotent — skips steps already applied (--force to redo).

AllowUsers modes (--allow-users):
  auto   wheel admins if any, else login users (merges existing sshd)
  wheel  wheel group only
  login  all /home/* accounts

Round 2 (strict research): firewall public zone · ssh only · disable avahi/cups/bt
  ./system/hardening_round2.sh --dry-run --yes
  ./system/hardening_round2.sh --yes
  ./system/security_audit.sh
  ./system/security_audit.sh --summary
  ./system/security_audit.sh --findings --compare
  ./system/security_audit.sh --plan
  ./system/hardening_round1.sh --status
  ./system/hardening_round1.sh --dry-run
  ./system/hardening_round1.sh --yes --allow-users wheel
  ./system/hardening_services_audit.sh

Baselines: /data/logs/hardening/<host>/<stamp>/ (or logs/hardening/)
EOF
      menu_pause
      return 0
      ;;
    4) menu_run_script_scroll system/hardening_round1.sh --status; return 0 ;;
    *) return 2 ;;
  esac
}

system_menu_hardening() {
  menu_loop "OS hardening" "Round 1 safe · audit before Round 2" \
    _system_hardening_items _system_hardening_dispatch
}

# ---------- Logs submenu ----------
_system_logs_items() {
  theme_section "Overview"
  menu_item 1 "Engine status"
  menu_item 2 "List logs + archive + backups"
  menu_item 3 "Summary (system_update.log)"
  menu_item 4 "Issues / errors (system_update.log)"
  theme_section "Tail / follow"
  menu_item 5 "Tail system_update.log" "last 50"
  menu_item 6 "Tail fedora_rebuild.log" "last 50"
  menu_item 7 "Tail mobsf.log" "last 50"
  menu_item 8 "Follow system_update.log" "Ctrl+C"
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

system_menu_help() {
  menu_help_docs_loop "system/README.md" "guides · index · logs"
}

_system_main_items() {
  theme_section "Workstation readiness"
  menu_item_lane 1 system "Workstation readiness" "daily driver · btrfs · LUKS · vbox"
  theme_section "Host baseline"
  menu_item_lane 2 system "Host information" "system snapshot"
  menu_item_lane 3 system "Disk and memory" "quick health dashboard"
  menu_item_lane 4 system "Fresh install baseline" "report → logs/"
  menu_item_lane 5 system "Rebuild readiness" "pre-rebuild validation"
  theme_section "Operations"
  menu_item_lane 6 system "Update Fedora" "quiet summary · full log saved"
  menu_item_lane 7 system "View logs" "log_engine · tail · follow"
  menu_item_lane 8 system "Cleanup" "logs · dnf · repo fix"
  theme_section "Security"
  menu_item_lane 9 system "OS hardening" "Round 1 · services audit"
  menu_item_lane_exit
}

_system_main_dispatch() {
  case "$1" in
    0) menu_lane_handle_main_exit ;;
    1) system_menu_readiness; return 0 ;;
    2) menu_run_script_scroll system/system_info.sh; menu_pause; return 0 ;;
    3) system_menu_disk_memory; return 0 ;;
    4) menu_run_script_scroll system/fresh_install_check.sh; menu_pause; return 0 ;;
    5) menu_run_script_scroll system/rebuild_readiness_check.sh; menu_pause; return 0 ;;
    6)
      info "Update logs to: $(log_dir)/system_update.log"
      menu_run_sudo_env_script_scroll system/system_update.sh --quick
      menu_pause
      return 0
      ;;
    7) system_menu_logs; return 0 ;;
    8) system_menu_cleanup; return 0 ;;
    9) system_menu_hardening; return 0 ;;
    *) return 2 ;;
  esac
}

system_main_menu() {
  local prev_header="${MENU_HEADER_FN}"
  menu_set_header_fn system_menu_maintenance_header
  menu_loop "System maintenance" "host · updates · logs · cleanup" \
    _system_main_items _system_main_dispatch
  menu_set_header_fn "${prev_header}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
