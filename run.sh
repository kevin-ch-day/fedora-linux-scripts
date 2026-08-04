#!/usr/bin/env bash
# run.sh — Fedora workstation control plane (primary entry point)
# Version: 1.8.0
#
# Run: ./run.sh [--help|--check|--daily|--onboard|…]
#
# MobSF is the one separate module entry: ./mobsf.sh

set -euo pipefail

FEDORA_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Normalize the global display flag before any dispatch. This keeps it out of
# nested command parsers and permits either `--no-color --check` or
# `--check --no-color`.
_fedora_args=()
for _fedora_arg in "$@"; do
  case "${_fedora_arg}" in
    --no-color)
      # Sourced common/theme libraries read this global display override.
      # shellcheck disable=SC2034
      FEDORA_NO_COLOR=1
      ;;
    *) _fedora_args+=("${_fedora_arg}") ;;
  esac
done
set -- "${_fedora_args[@]}"
unset _fedora_args _fedora_arg

# Inspect dispatch is intentionally before library and menu initialization.
# This preserves the no-write/no-sudo inspection contract.
if [[ "${1:-}" == "--inspect" ]]; then
  shift
  INSPECT_PYTHON="${PYTHON:-python3}"
  if ! command -v "${INSPECT_PYTHON}" >/dev/null 2>&1; then
    printf 'error: %s is required for host inspection\n' "${INSPECT_PYTHON}" >&2
    exit 127
  fi
  exec "${INSPECT_PYTHON}" "${FEDORA_ROOT}/libexec/inspect_host.py" "$@"
fi

# shellcheck source=lib/menu.sh
source "${FEDORA_ROOT}/lib/menu.sh"
# shellcheck source=lib/health_snapshot.sh
source "${FEDORA_ROOT}/lib/health_snapshot.sh"
# shellcheck source=system/lib/menu.sh
source "${FEDORA_ROOT}/system/lib/menu.sh"
# shellcheck source=lib/workflows.sh
source "${FEDORA_ROOT}/lib/workflows.sh"
menu_init "Fedora Workstation Control" "${FEDORA_ROOT}" 1

_fedora_run_check() {
  # shellcheck source=lib/check.sh
  source "${FEDORA_ROOT}/lib/check.sh"
  local full=0 fix_repos=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --full) full=1; shift ;;
      --fix-repos) fix_repos=1; shift ;;
      *) die "Unknown option for --check: $1 (try: --check [--full] [--fix-repos])" ;;
    esac
  done
  fedora_toolkit_check "${FEDORA_ROOT}" "${full}" "${fix_repos}"
}

_fedora_run_update() {
  local quick="${1:-0}"
  local -a args=()
  (( quick )) && args+=(--quick)
  info "Update logs to: $(log_dir)/system_update.log"
  if [[ -t 0 && -t 1 ]]; then
    system_menu_run_update "${quick}"
    return $?
  fi
  exec sudo -E bash "${FEDORA_ROOT}/system/system_update.sh" "${args[@]}"
}

_fedora_run_onboard() {
  local skip_setup=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skip-setup) skip_setup=1; shift ;;
      *) die "Unknown option for --onboard: $1" ;;
    esac
  done
  workflow_onboard_fresh_machine "${FEDORA_ROOT}" "${skip_setup}"
}

_fedora_run_daily_sync() {
  local quick="${1:-0}"
  if [[ -t 0 && -t 1 ]]; then
    workflow_daily_sync "${quick}" "${FEDORA_ROOT}"
    return $?
  fi
  workflow_run_update "${quick}" "${FEDORA_ROOT}" || return $?
  workflow_run_post_update "${FEDORA_ROOT}"
}

_fedora_open_lane() {
  local lane="$1"
  local ec=0
  case "${lane}" in
    1) _fedora_run_update 0 || ec=$? ;;
    2) _fedora_run_daily_sync 0 || ec=$? ;;
    3) bash "${FEDORA_ROOT}/system/post_update_check.sh" || ec=$? ;;
    4) FEDORA_FROM_PICKER=1 bash "${FEDORA_ROOT}/system/system.sh" || ec=$? ;;
    5) bash "${FEDORA_ROOT}/system/research_doctor.sh" --android-only || ec=$? ;;
    6) _fedora_run_check || ec=$? ;;
    *) die "Invalid menu item: ${lane} (use 1–6)" ;;
  esac
  if (( ec != 0 )); then
    warn "Menu item exited with status ${ec}"
  fi
  return "${ec}"
}

# Non-interactive menu shortcut (must run before option parsing consumes args)
if [[ $# -eq 1 ]] && [[ "$1" =~ ^[1-6]$ ]]; then
  _fedora_open_lane "$1"
  exit $?
fi

fedora_usage() {
  cat <<EOF
Fedora Workstation Toolkit — daily control starts with ./run.sh

Quick start:
  ./setup.sh                 First clone: provision tools and workstation components
  ./run.sh                   Interactive main menu
  ./run.sh --daily           Update + post-update check (recommended daily)
  ./run.sh --check           Validate toolkit readiness
  ./setup.sh research --plan  Review the research workstation profile
  ./setup.sh list             Profile catalog

More shortcuts:
  ./run.sh 1                 Update Fedora (non-interactive)
  ./run.sh 2                 Update + post-update check (daily sync)
  ./run.sh --update          Full dnf upgrade (sudo)
  ./run.sh --daily --quick   Faster daily sync (skip rpm -Va on update step)
  ./run.sh --check          All-in-one readiness (validate · smoke · rebuild)
  ./run.sh --check --full   Include full smoke + Fedora doctor
  ./run.sh --check --fix-repos   Fix DNF repos (sudo) then re-check
  ./run.sh --daily-driver-check
  ./run.sh --inspect         Non-mutating host inventory (JSON by default)
  ./run.sh --post-update-check
  ./run.sh --disk-summary
  ./run.sh --doctor
  ./run.sh --baseline
  ./run.sh --smoke          Dynamic CLI/menu tests
  ./run.sh --check          Repo readiness (validate · smoke · rebuild check)

MobSF stack (separate lifecycle):
  ./mobsf.sh
  ./mobsf.sh --doctor

Usage: $(basename "$0") [options|menu-item]

Menu item (non-interactive):
  1                  Update Fedora (full)
  2                  Update + post-update check (daily sync)
  3                  Post-update check only
  4                  System maintenance menu
  5                  System health check (doctor)
  6                  Toolkit self-test

Options:
  --help, -h         Show this help
  --no-color         Plain text output (also: NO_COLOR=1)
  --update           Full Fedora update (sudo; logs to system_update.log)
  --update --quick   Faster update (skip rpm -Va verify)
  --daily            Update then post-update check (same as menu [2])
  --daily --quick    Daily sync with quick update step
  --onboard          Fresh machine wizard (setup → check → research setup)
  --onboard --skip-setup  Onboard from check step (after --check)
  FEDORA_THEME       dark (default) or light — console color palette
  FEDORA_THEME_DENSITY  normal (default) or compact — menu spacing
  --check            Validate + smoke + rebuild readiness (add --full or --fix-repos)
  --smoke          Run ./smoke_test.sh --quick (append --full for full doctors)
  --fix-repos        Fix DNF .repo permissions (sudo — common rebuild-check fix)
  --daily-driver-check  Read-only daily driver / workstation readiness
  --inspect [opts]      Detailed no-sudo host inventory; no writes without --save
  --post-update-check   Validate system after dnf upgrade
  --disk-summary        Disk/memory snapshot (auto-refresh if older than 15m)
  --doctor           Fedora doctor (repo · lanes · workstation health)
  --baseline         Fresh-install host baseline report (read-only → logs/)
  --security-audit   Read-only security audit → logs/security_audit/
  --audit-summary    Fast live findings only (no full report)
  --audit-plan       Ordered remediation plan from live findings
  --host-context     Live host snapshot (users · network · posture)
  --system           Open System maintenance menu
  --dev              Open Developer tools
  --android          Open Android RE tools

Area routes:
  ./run.sh --system        Host · updates · logs · cleanup
  ./run.sh --dev           Developer tools · desktop · virtualization · web
  ./run.sh --android       Android RE tools · verify · ADB

Fresh install flow:
  ./setup.sh
  ./setup.sh --guided               # guided: check → research setup
  ./setup.sh research --yes
  ./setup.sh list                    # android-re, dev-stack, web-stack, …
  ./setup.sh research --plan

See: docs/GETTING-STARTED.md
Root: ${FEDORA_ROOT}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) fedora_usage; exit 0 ;;
    --version|-V)
      echo "fedora-linux-scripts run.sh 1.8.0"
      exit 0
      ;;
    --check)
      shift
      _fedora_run_check "$@"
      exit $?
      ;;
    --smoke)
      shift
      if [[ "${1:-}" == "--full" ]]; then
        shift
        exec bash "${FEDORA_ROOT}/smoke_test.sh"
      fi
      exec bash "${FEDORA_ROOT}/smoke_test.sh" --quick "$@"
      ;;
    --fix-repos)
      shift
      exec sudo bash "${FEDORA_ROOT}/system/fix_dnf_repo_permissions.sh" "$@"
      ;;
    --update)
      shift
      quick=0
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --quick) quick=1; shift ;;
          *) break ;;
        esac
      done
      _fedora_run_update "${quick}"
      exit $?
      ;;
    --daily)
      shift
      quick=0
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --quick) quick=1; shift ;;
          *) break ;;
        esac
      done
      _fedora_run_daily_sync "${quick}"
      exit $?
      ;;
    --onboard)
      shift
      _fedora_run_onboard "$@"
      exit $?
      ;;
    --daily-driver-check) shift; exec bash "${FEDORA_ROOT}/system/daily_driver_check.sh" "$@" ;;
    --post-update-check) shift; exec bash "${FEDORA_ROOT}/system/post_update_check.sh" "$@" ;;
    --disk-summary) shift; exec bash "${FEDORA_ROOT}/system/health_snapshot.sh" --show "$@" ;;
    --doctor) shift; exec bash "${FEDORA_ROOT}/system/research_doctor.sh" --android-only "$@" ;;
    --baseline) shift; exec bash "${FEDORA_ROOT}/system/fresh_install_check.sh" "$@" ;;
    --security-audit) shift; exec bash "${FEDORA_ROOT}/system/security_audit.sh" "$@" ;;
    --audit-summary) shift; exec bash "${FEDORA_ROOT}/system/security_audit.sh" --summary "$@" ;;
    --audit-plan) shift; exec bash "${FEDORA_ROOT}/system/security_audit.sh" --plan "$@" ;;
    --host-context) shift; exec bash "${FEDORA_ROOT}/system/host_context.sh" "$@" ;;
    --system) shift; FEDORA_FROM_PICKER=1 exec bash "${FEDORA_ROOT}/system/system.sh" "$@" ;;
    --dev)
      shift
      if (( $# == 0 )); then
        FEDORA_FROM_PICKER=1 exec bash "${FEDORA_ROOT}/dev/dev.sh" --developer-tools
      fi
      FEDORA_FROM_PICKER=1 exec bash "${FEDORA_ROOT}/dev/dev.sh" "$@"
      ;;
    --android) shift; FEDORA_FROM_PICKER=1 exec bash "${FEDORA_ROOT}/android/android.sh" "$@" ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

fedora_main_header() {
  local health_line=""
  menu_clear_screen
  theme_lane_banner "${MENU_APP_NAME}" main
  theme_meta_line "HOST / $(hostname) · USER / $(real_user)"
  theme_meta_line "ROOT / ${MENU_ROOT}"
  if health_line="$(health_snapshot_status_line_from_file 2>/dev/null || true)" && [[ -n "${health_line}" ]]; then
    theme_meta_line "${health_line}"
  fi
  menu_hr
  theme_page_title "Main menu"
  theme_meta_line "[1] update · [2] daily sync · ./run.sh --help for CLI"
}

_fedora_main_items() {
  theme_section "Everyday — start here"
  menu_item_lane 1 update "Update Fedora" "sudo · dnf upgrade · full verify · log saved"
  menu_item_lane 2 postupdate "Update + post-update check" "recommended daily workflow"
  menu_item_lane 3 postupdate "Post-update check only" "after manual dnf upgrade"
  theme_section "Maintenance and health"
  menu_item_lane 4 system "System maintenance" "logs · cleanup · disk · hardening"
  menu_item_lane 5 audit "System health check" "Fedora doctor · repos · lane entry points"
  menu_item_lane 6 check "Repository self-test" "validate · smoke · readiness"
  echo
  menu_item_exit
}

_fedora_main_dispatch() {
  case "$1" in
    0) info "Main menu closed. Run ./run.sh to return."; exit 0 ;;
    1) system_menu_run_update 0; menu_pause; return 0 ;;
    2) system_menu_run_daily_sync 0; menu_pause; return 0 ;;
    3) menu_run_script_scroll system/post_update_check.sh; menu_pause; return 0 ;;
    4) FEDORA_FROM_PICKER=1 bash "${FEDORA_ROOT}/system/system.sh"; return 0 ;;
    5)
      menu_run_script_scroll system/research_doctor.sh --android-only
      menu_pause
      return 0
      ;;
    6)
      local prev="${MENU_SCROLL_MODE}"
      MENU_SCROLL_MODE=1
      _fedora_run_check || true
      MENU_SCROLL_MODE="${prev}"
      menu_pause
      return 0
      ;;
    *) return 2 ;;
  esac
}

main_menu() {
  health_snapshot_startup_refresh
  menu_set_header_fn fedora_main_header
  theme_set_lane main
  menu_loop "Main menu" "" _fedora_main_items _fedora_main_dispatch
}

main_menu
