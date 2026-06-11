#!/usr/bin/env bash
# run.sh — Fedora workstation control plane (lane picker + rebuild + doctor CLI)
# Version: 1.0.1
#
# Run: ./run.sh [--help|--check|--smoke|--doctor|--baseline|--rebuild-check|--rebuild*|--system|--dev|--android]
#
# Compatibility: ./fedora.sh → same as ./run.sh
# MobSF is separate: ./mobsf.sh (not a lane here).

set -euo pipefail

FEDORA_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# --no-color before lib load (also respects NO_COLOR via theme_init)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-color) FEDORA_NO_COLOR=1; shift ;;
    *) break ;;
  esac
done

# shellcheck source=lib/menu.sh
source "${FEDORA_ROOT}/lib/menu.sh"
# shellcheck source=lib/health_snapshot.sh
source "${FEDORA_ROOT}/lib/health_snapshot.sh"
# shellcheck source=system/lib/menu.sh
source "${FEDORA_ROOT}/system/lib/menu.sh"
# shellcheck source=dev/lib/menu.sh
source "${FEDORA_ROOT}/dev/lib/menu.sh"
# shellcheck source=android/lib/menu.sh
source "${FEDORA_ROOT}/android/lib/menu.sh"

menu_init "Fedora Workstation Toolkit" "${FEDORA_ROOT}" 1

_fedora_run_rebuild() {
  FEDORA_REBUILD_VIA_FEDORA=1 exec bash "${FEDORA_ROOT}/fedora_rebuild.sh" "$@"
}

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

_fedora_inline_menu() {
  local header_fn="$1"
  local lane="$2"
  local menu_fn="$3"
  local prev_header="${MENU_HEADER_FN}"
  local prev_lane="${THEME_LANE:-main}"
  local prev_parent="${MENU_PARENT_CONTEXT:-}"

  menu_set_header_fn "${header_fn}"
  theme_set_lane "${lane}"
  MENU_PARENT_CONTEXT="main-menu"
  "${menu_fn}"
  menu_set_header_fn "${prev_header}"
  theme_set_lane "${prev_lane}"
  MENU_PARENT_CONTEXT="${prev_parent}"
}

_fedora_open_lane() {
  local lane="$1"
  local ec=0
  case "${lane}" in
    1) FEDORA_FROM_PICKER=1 bash "${FEDORA_ROOT}/system/system.sh" || ec=$? ;;
    2) FEDORA_FROM_PICKER=1 bash "${FEDORA_ROOT}/dev/dev.sh" --developer-tools || ec=$? ;;
    3) FEDORA_FROM_PICKER=1 bash "${FEDORA_ROOT}/dev/dev.sh" --desktop-environments || ec=$? ;;
    4) FEDORA_FROM_PICKER=1 bash "${FEDORA_ROOT}/dev/dev.sh" --virtualization || ec=$? ;;
    5) FEDORA_FROM_PICKER=1 bash "${FEDORA_ROOT}/dev/dev.sh" --web-stack || ec=$? ;;
    6) FEDORA_FROM_PICKER=1 bash "${FEDORA_ROOT}/android/android.sh" || ec=$? ;;
    7) FEDORA_REBUILD_VIA_FEDORA=1 bash "${FEDORA_ROOT}/fedora_rebuild.sh" || ec=$? ;;
    8) bash "${FEDORA_ROOT}/system/research_doctor.sh" --android-only || ec=$? ;;
    9) FEDORA_FROM_PICKER=1 bash "${FEDORA_ROOT}/system/system.sh" audit || ec=$? ;;
    10) _fedora_run_check || ec=$? ;;
    *) die "Invalid menu item: ${lane} (use 1–10)" ;;
  esac
  if (( ec != 0 )); then
    warn "Menu item exited with status ${ec} — returning to main menu"
  fi
}

# Non-interactive lane shortcut (must run before option parsing consumes args)
if [[ $# -eq 1 ]] && [[ "$1" =~ ^([1-9]|10)$ ]]; then
  _fedora_open_lane "$1"
  exit 0
fi

fedora_usage() {
  cat <<EOF
Fedora Workstation Toolkit — main entry point.

Quick start:
  ./run.sh
  ./run.sh --check          All-in-one readiness (validate · smoke · rebuild)
  ./run.sh --check --full   Include full smoke + Fedora doctor
  ./run.sh --check --fix-repos   Fix DNF repos (sudo) then re-check
  ./run.sh --daily-driver-check
  ./run.sh --post-update-check
  ./run.sh --disk-summary
  ./run.sh --doctor
  ./run.sh --baseline
  ./run.sh --rebuild-check
  ./run.sh --rebuild
  ./run.sh --smoke          Dynamic CLI/menu tests
  ./setup.sh                Repo readiness (validate · optional smoke)

Compatibility: ./fedora.sh is a wrapper for ./run.sh (older docs/scripts).

MobSF stack (separate lifecycle):
  ./mobsf.sh
  ./mobsf.sh --doctor

Usage: $(basename "$0") [options|menu-item]

Menu item (non-interactive):
  1..10              Run one main-menu item once, then exit

Options:
  --help, -h         Show this help
  --no-color         Plain text output (also: NO_COLOR=1)
  FEDORA_THEME       dark (default) or light — console color palette
  FEDORA_THEME_DENSITY  normal (default) or compact — menu spacing
  ./theme_preview.sh Preview all theme elements
  --check            Validate + smoke + rebuild readiness (add --full or --fix-repos)
  --smoke          Run ./smoke_test.sh --quick (append --full for full doctors)
  --fix-repos        Fix DNF .repo permissions (sudo — common rebuild-check fix)
  --daily-driver-check  Read-only daily driver / workstation readiness
  --post-update-check   Validate system after dnf upgrade
  --disk-summary        Disk/memory snapshot (auto-refresh if older than 15m)
  --doctor           Fedora doctor (repo · lanes · workstation health)
  --baseline         Fresh-install host baseline report (read-only → logs/)
  --security-audit   Read-only security audit → logs/security_audit/
  --audit-summary    Fast live findings only (no full report)
  --audit-plan       Ordered remediation plan from live findings
  --host-context     Live host snapshot (users · network · posture)
  --rebuild-check    Pre-rebuild readiness (no installs)
  --rebuild [opts]   Guided rebuild (passes options to rebuild engine)
  --rebuild-yes      Rebuild with --yes
  --dry-run          Rebuild dry-run
  --system           Open System maintenance menu
  --dev              Open Developer tools
  --android          Open Android RE tools

Area launchers:
  ./system/system.sh       Host · updates · logs · cleanup
  ./dev/dev.sh --developer-tools
  ./dev/dev.sh --desktop-environments
  ./dev/dev.sh --virtualization
  ./dev/dev.sh --web-stack
  ./android/android.sh     Android RE tools · verify · ADB (MobSF: ./mobsf.sh)

Fresh install flow:
  ./setup.sh
  ./run.sh --check
  ./run.sh --doctor
  ./run.sh --rebuild

Legacy scripts in ./legacy/ are disabled reference only.
See: docs/GETTING-STARTED.md
Root: ${FEDORA_ROOT}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) fedora_usage; exit 0 ;;
    --no-color) shift ;;
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
    --rebuild) shift; _fedora_run_rebuild "$@" ;;
    --rebuild-yes) shift; _fedora_run_rebuild --yes "$@" ;;
    --dry-run) shift; _fedora_run_rebuild --dry-run "$@" ;;
    --daily-driver-check) shift; exec bash "${FEDORA_ROOT}/system/daily_driver_check.sh" "$@" ;;
    --post-update-check) shift; exec bash "${FEDORA_ROOT}/system/post_update_check.sh" "$@" ;;
    --disk-summary) shift; exec bash "${FEDORA_ROOT}/system/health_snapshot.sh" --show "$@" ;;
    --doctor) shift; exec bash "${FEDORA_ROOT}/system/research_doctor.sh" --android-only "$@" ;;
    --baseline) shift; exec bash "${FEDORA_ROOT}/system/fresh_install_check.sh" "$@" ;;
    --security-audit) shift; exec bash "${FEDORA_ROOT}/system/security_audit.sh" "$@" ;;
    --audit-summary) shift; exec bash "${FEDORA_ROOT}/system/security_audit.sh" --summary "$@" ;;
    --audit-plan) shift; exec bash "${FEDORA_ROOT}/system/security_audit.sh" --plan "$@" ;;
    --host-context) shift; exec bash "${FEDORA_ROOT}/system/host_context.sh" "$@" ;;
    --rebuild-check) shift; exec bash "${FEDORA_ROOT}/system/rebuild_readiness_check.sh" "$@" ;;
    --system) shift; FEDORA_FROM_PICKER=1 exec bash "${FEDORA_ROOT}/system/system.sh" "$@" ;;
    --dev) shift; FEDORA_FROM_PICKER=1 exec bash "${FEDORA_ROOT}/dev/dev.sh" --developer-tools "$@" ;;
    --android) shift; FEDORA_FROM_PICKER=1 exec bash "${FEDORA_ROOT}/android/android.sh" "$@" ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

fedora_main_header() {
  local health_line=""
  menu_clear_screen
  theme_lane_banner "${MENU_APP_NAME}" main
  theme_meta_line "Host: $(hostname) · User: $(real_user)"
  theme_meta_line "Root: ${MENU_ROOT}"
  if health_line="$(health_snapshot_status_line_from_file 2>/dev/null || true)" && [[ -n "${health_line}" ]]; then
    theme_meta_line "${health_line}"
  fi
  menu_hr
  theme_page_title "Main menu"
  theme_meta_line "choose a lane, a rebuild path, or a health check"
}

_fedora_main_items() {
  theme_section "Workstation areas"
  menu_item_lane 1 system "System maintenance" "daily readiness · updates · logs · cleanup"
  menu_item_lane 2 dev "Developer tools" "git · vscode · shell helpers"
  menu_item_lane 3 desktop "Desktop environments" "cinnamon · kde · mate · lxqt"
  menu_item_lane 4 virt "Virtualization & containers" "podman · docker · kvm · virtualbox"
  menu_item_lane 5 web "Web/database stack" "apache · mariadb · php · phpmyadmin"
  menu_item_lane 6 android "Android RE tools" "sdk · adb · jadx · apktool"
  theme_section "Setup and health"
  menu_item_lane 7 rebuild "Guided rebuild" "install and configure this workstation"
  menu_item_lane 8 audit "System health check" "Fedora doctor · repos · Android RE entry points"
  menu_item_lane 9 audit "Hardening and services" "firewall · services · listening ports"
  menu_item_lane 10 check "Toolkit self-test" "validate · smoke · rebuild readiness"
  echo
  menu_item_exit
}

_fedora_main_dispatch() {
  case "$1" in
    0) info "Main menu closed. Run ./run.sh to return."; exit 0 ;;
    1)
      _fedora_inline_menu system_menu_header system system_main_menu
      return 0
      ;;
    2) _fedora_inline_menu dev_menu_developer_header dev dev_menu_developer_tools; return 0 ;;
    3) _fedora_inline_menu dev_menu_desktop_header dev dev_menu_desktop_environments; return 0 ;;
    4) _fedora_inline_menu dev_menu_virtualization_header dev dev_menu_infrastructure; return 0 ;;
    5) _fedora_inline_menu dev_menu_web_header dev dev_menu_web_stack; return 0 ;;
    6) _fedora_inline_menu android_menu_main_header android android_main_menu; return 0 ;;
    7)
      info "Guided rebuild (confirm each step)"
      FEDORA_FROM_MENU=1 FEDORA_REBUILD_VIA_FEDORA=1 bash "${FEDORA_ROOT}/fedora_rebuild.sh" || true
      menu_pause
      return 0
      ;;
    8)
      menu_run_script_scroll system/research_doctor.sh --android-only
      menu_pause
      return 0
      ;;
    9)
      _fedora_inline_menu system_menu_header system system_menu_hardening
      return 0
      ;;
    10)
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
