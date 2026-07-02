#!/usr/bin/env bash
# system/lib/menu.sh — System maintenance menus (host, maintenance, logs)
# Version: 0.5.0
#
# Standalone:  ./system/system.sh
# From main:   ./run.sh → [9] System maintenance · [1] Update Fedora
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

# quick=1 → skip slow rpm -Va (daily driver); quick=0 → full verify pass
system_menu_run_update() {
  local quick="${1:-0}"
  local -a args=()
  (( quick )) && args+=(--quick)
  info "Update logs to: $(log_dir)/system_update.log"
  menu_run_sudo_env_script_scroll system/system_update.sh "${args[@]}"
  theme_status_info "After upgrade: Post-update check (main [3] or --post-update-check)"
}

system_menu_run_daily_sync() {
  local quick="${1:-0}"
  local ec=0
  # shellcheck source=../../lib/workflows.sh
  source "${_FEDORA_ROOT}/lib/workflows.sh"
  if workflow_daily_sync "${quick}" "${_FEDORA_ROOT}"; then
    ec=0
  else
    ec=$?
  fi
  return "${ec}"
}

# ---------- Security audit submenu ----------
_system_security_audit_items() {
  menu_item 1 "Security audit" "full report → logs/"
  menu_item 2 "Audit summary" "fast · live findings only"
  menu_item 3 "Audit action plan" "ordered remediation steps"
  menu_item 4 "Host context" "users · network · posture snapshot"
  menu_item_back
}

_system_security_audit_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script_scroll system/security_audit.sh; return 0 ;;
    2) menu_run_script_scroll system/security_audit.sh --summary; return 0 ;;
    3) menu_run_script_scroll system/security_audit.sh --plan; return 0 ;;
    4) menu_run_script_scroll system/host_context.sh --summary; return 0 ;;
    *) return 2 ;;
  esac
}

system_menu_security_audit() {
  menu_loop "Security audit" "read-only · findings · remediation plan" \
    _system_security_audit_items _system_security_audit_dispatch
}

# ---------- Round 1 hardening submenu ----------
_system_hardening_round1_items() {
  menu_item 1 "OS hardening Round 1" "sudo · auto-detect · idempotent"
  menu_item 2 "Round 1 status" "read-only · what's applied"
  menu_item 3 "Services audit" "profile-aware · read-only"
  menu_item 4 "Help" "hardening notes"
  menu_item_back
}

_system_hardening_round1_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script_scroll system/hardening_round1.sh; menu_pause; return 0 ;;
    2) menu_run_script_scroll system/hardening_round1.sh --status; return 0 ;;
    3) menu_run_script_scroll system/hardening_services_audit.sh; menu_pause; return 0 ;;
    4)
      cat <<EOF

Round 1 — safe OS hardening
───────────────────────────
Baseline, SELinux, SSH, sysctl, journald, firewalld.
Idempotent — skips steps already applied (--force to redo).

  ./system/hardening_round1.sh --status
  ./system/hardening_round1.sh --dry-run
  ./system/hardening_round1.sh --yes --allow-users wheel

Baselines: logs/hardening/<host>/<stamp>/
EOF
      menu_pause
      return 0
      ;;
    *) return 2 ;;
  esac
}

system_menu_hardening_round1() {
  menu_loop "Round 1 — safe baseline" "SELinux · SSH · sysctl · firewalld" \
    _system_hardening_round1_items _system_hardening_round1_dispatch
}

# ---------- Round 2 strict submenu ----------
_system_hardening_round2_items() {
  theme_section "Strict profile — review audit first"
  menu_item_danger 1 "OS hardening Round 2" "sudo · firewall + services"
  menu_item_danger 2 "Strict firewall (SSH only)" "custom zone · wired NM"
  menu_item_danger 3 "Listening hardening" "MariaDB · Avahi · LLMNR · BT/Wi-Fi"
  menu_item_danger 4 "Wired only (BT/Wi-Fi off)" "wired Ethernet · mask BT"
  menu_item_back
}

_system_hardening_round2_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script_scroll system/hardening_round2.sh; menu_pause; return 0 ;;
    2) menu_run_script_scroll system/hardening_firewall_strict.sh; menu_pause; return 0 ;;
    3) menu_run_script_scroll system/hardening_listening.sh; menu_pause; return 0 ;;
    4) menu_run_script_scroll system/hardening_wired_only.sh; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

system_menu_hardening_round2() {
  menu_loop "Round 2 — strict profile" "firewall · services · listening" \
    _system_hardening_round2_items _system_hardening_round2_dispatch
}

# ---------- Hardening hub ----------
_system_hardening_hub_items() {
  theme_section "Baseline"
  menu_item 1 "Round 1 — safe baseline" "SELinux · SSH · sysctl"
  theme_section "Audit"
  menu_item 2 "Security audit" "findings · summary · action plan"
  theme_section "Strict profile"
  menu_item_danger 3 "Round 2 — strict profile" "firewall · services · danger zone"
  menu_item_back
}

_system_hardening_hub_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) system_menu_hardening_round1; return 0 ;;
    2) system_menu_security_audit; return 0 ;;
    3) system_menu_hardening_round2; return 0 ;;
    *) return 2 ;;
  esac
}

system_menu_hardening() {
  menu_loop "Hardening and security" "Round 1 safe · audit · Round 2 strict" \
    _system_hardening_hub_items _system_hardening_hub_dispatch
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
  local age_hint
  age_hint="$(health_snapshot_menu_age_hint)"
  theme_section "Summary"
  menu_item 1 "View disk/memory summary" "${age_hint}"
  menu_item 2 "Refresh snapshot now" "updates runtime/health/latest.*"
  menu_item 3 "Export full diagnostic report" "large dirs · lsblk · saved to history/"
  theme_section "Related"
  menu_item 4 "More readiness checks" "btrfs · LUKS · VirtualBox · fresh install"
  menu_item_back
}

_system_disk_memory_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script_scroll system/health_snapshot.sh --show; menu_pause; return 0 ;;
    2) menu_run_script_scroll system/health_snapshot.sh --refresh; menu_pause; return 0 ;;
    3) menu_run_script_scroll system/health_snapshot.sh --export; menu_pause; return 0 ;;
    4) system_menu_readiness; return 0 ;;
    *) return 2 ;;
  esac
}

system_menu_disk_memory() {
  menu_loop "Disk and memory" "RAM · disks · cleanup · top memory" \
    _system_disk_memory_items _system_disk_memory_dispatch
}

# ---------- Extended readiness submenu (btrfs · LUKS · vbox · recovery) ----------
_system_readiness_items() {
  theme_section "Stabilization"
  menu_item 1 "Btrfs health" "device stats · scrub status"
  menu_item 2 "LUKS readiness" "keyslots (sudo) · header backups"
  menu_item 3 "VirtualBox readiness" "modules · vboxdrv · packages"
  menu_item 4 "Package / update noise" "PackageKit · dnf · flatpak"
  theme_section "Host baseline"
  menu_item 5 "Fresh install report" "baseline report → logs/"
  theme_section "Recovery"
  menu_item 6 "Backup current state" "export for reinstall"
  menu_item 7 "Host context snapshot" "users · network · posture"
  menu_item_back
}

_system_readiness_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) menu_run_script_scroll system/btrfs_health.sh; menu_pause; return 0 ;;
    2) menu_run_script_scroll system/luks_readiness.sh; menu_pause; return 0 ;;
    3) menu_run_script_scroll system/virtualbox_readiness.sh; menu_pause; return 0 ;;
    4) menu_run_script_scroll system/package_noise.sh; menu_pause; return 0 ;;
    5) menu_run_script_scroll system/fresh_install_check.sh; menu_pause; return 0 ;;
    6) menu_run_script_scroll system/backup_state.sh; menu_pause; return 0 ;;
    7) menu_run_script_scroll system/host_context.sh --summary; menu_pause; return 0 ;;
    *) return 2 ;;
  esac
}

system_menu_readiness() {
  menu_loop "More readiness checks" "btrfs · LUKS · VirtualBox · fresh install" \
    _system_readiness_items _system_readiness_dispatch
}

# ---------- OS hardening (legacy flat menu removed — use hub above) ----------

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
  theme_section "Updates — start here"
  menu_item_lane 1 update "Update Fedora" "sudo · dnf upgrade · full verify · log saved"
  menu_item_lane 2 postupdate "Update + post-update check" "recommended daily workflow"
  menu_item_lane 3 postupdate "Post-update check only" "reboot · btrfs · failed units"
  menu_item_lane 4 update "Quick update" "skip rpm -Va · faster"
  theme_section "Readiness"
  menu_item_lane 5 readiness "Daily driver check" "btrfs · LUKS · VirtualBox · services"
  menu_item_lane 6 rebuild "Rebuild readiness" "pre-rebuild validation"
  theme_section "Host information"
  menu_item_lane 7 host "Host snapshot" "OS · kernel · hardware · mounts"
  menu_item_lane 8 disk "Disk and memory" "storage · RAM · swap"
  theme_section "Operations"
  menu_item_lane 9 logs "View logs" "recent logs · follow · search"
  menu_item_lane 10 cleanup "Cleanup" "logs · dnf cache · repo permissions"
  theme_section "Security"
  menu_item_lane 11 audit "Hardening and security" "Round 1 · audit · Round 2 strict"
  menu_item_lane_exit
}

_system_main_dispatch() {
  case "$1" in
    0) menu_lane_handle_main_exit ;;
    1) system_menu_run_update 0; menu_pause; return 0 ;;
    2) system_menu_run_daily_sync 0; menu_pause; return 0 ;;
    3) menu_run_script_scroll system/post_update_check.sh; menu_pause; return 0 ;;
    4) system_menu_run_update 1; menu_pause; return 0 ;;
    5) menu_run_script_scroll system/daily_driver_check.sh; menu_pause; return 0 ;;
    6) menu_run_script_scroll system/rebuild_readiness_check.sh; menu_pause; return 0 ;;
    7) menu_run_script_scroll system/system_info.sh; menu_pause; return 0 ;;
    8) system_menu_disk_memory; return 0 ;;
    9) system_menu_logs; return 0 ;;
    10) system_menu_cleanup; return 0 ;;
    11) system_menu_hardening; return 0 ;;
    *) return 2 ;;
  esac
}

system_main_menu() {
  local prev_header="${MENU_HEADER_FN}"
  menu_set_header_fn system_menu_maintenance_header
  menu_loop "System maintenance" "updates first · readiness · logs · cleanup" \
    _system_main_items _system_main_dispatch
  menu_set_header_fn "${prev_header}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
