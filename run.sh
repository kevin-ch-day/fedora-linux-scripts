#!/usr/bin/env bash
# run.sh — Fedora workstation control plane (primary entry point)
# Version: 1.7.0
#
# Run: ./run.sh [--help|--check|--daily|--rebuild|--install|--onboard|…]
#
# Legacy redirects (same behavior): ./fedora.sh  ·  ./fedora_rebuild.sh
# MobSF is separate: ./mobsf.sh

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

# shellcheck source=lib/workflows.sh
source "${FEDORA_ROOT}/lib/workflows.sh"
# shellcheck source=lib/rebuild.sh
source "${FEDORA_ROOT}/lib/rebuild.sh"

menu_init "Fedora Workstation Toolkit" "${FEDORA_ROOT}" 1

_fedora_run_rebuild() {
  fedora_rebuild_run "${FEDORA_ROOT}" "$@"
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
    4) _fedora_run_rebuild || ec=$? ;;
    5)
      if [[ -t 0 && -t 1 ]]; then
        menu_set_header_fn fedora_main_header
        theme_set_lane main
        MENU_PARENT_CONTEXT="main-menu"
        fedora_install_menu
      else
        info "Install workstation — interactive: ./run.sh --install"
        info "  Developer: ./run.sh --dev · Android: ./run.sh --android"
        info "  Full setup: ./run.sh --rebuild"
      fi
      ;;
    6) FEDORA_FROM_PICKER=1 bash "${FEDORA_ROOT}/system/system.sh" || ec=$? ;;
    7) bash "${FEDORA_ROOT}/system/research_doctor.sh" --android-only || ec=$? ;;
    8) _fedora_run_check || ec=$? ;;
    *) die "Invalid menu item: ${lane} (use 1–8)" ;;
  esac
  if (( ec != 0 )); then
    warn "Menu item exited with status ${ec}"
  fi
  return "${ec}"
}

# Non-interactive menu shortcut (must run before option parsing consumes args)
if [[ $# -eq 1 ]] && [[ "$1" =~ ^[1-8]$ ]]; then
  _fedora_open_lane "$1"
  exit $?
fi

fedora_usage() {
  cat <<EOF
Fedora Workstation Toolkit — you only need ./run.sh

Quick start:
  ./run.sh                   Interactive main menu
  ./run.sh --daily           Update + post-update check (recommended daily)
  ./run.sh --check           Validate toolkit readiness
  ./run.sh --rebuild         Full research workstation setup
  ./install.sh workstation --plan   Daily dev box (update + VS Code + KVM)
  ./run.sh --list-profiles          Profile catalog

More shortcuts:
  ./run.sh 1                 Update Fedora (non-interactive)
  ./run.sh 2                 Update + post-update check (daily sync)
  ./run.sh --update          Full dnf upgrade (sudo)
  ./run.sh --daily --quick   Faster daily sync (skip rpm -Va on update step)
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

Compatibility: ./fedora.sh and ./fedora_rebuild.sh redirect here (legacy names only).

MobSF stack (separate lifecycle):
  ./mobsf.sh
  ./mobsf.sh --doctor

Usage: $(basename "$0") [options|menu-item]

Menu item (non-interactive):
  1                  Update Fedora (full)
  2                  Update + post-update check (daily sync)
  3                  Post-update check only
  4                  Guided rebuild
  5                  Install workstation hub
  6                  System maintenance menu
  7                  System health check (doctor)
  8                  Toolkit self-test

Options:
  --help, -h         Show this help
  --no-color         Plain text output (also: NO_COLOR=1)
  --update           Full Fedora update (sudo; logs to system_update.log)
  --update --quick   Faster update (skip rpm -Va verify)
  --daily            Update then post-update check (same as menu [2])
  --daily --quick    Daily sync with quick update step
  --install          Install workstation hub (dev · desktop · Android · profiles)
  --profile NAME     Run install profile (passes through to ./install.sh)
  --list-profiles    Print install profile catalog (./install.sh list)
  --workstation      Run workstation profile (update + dev tools; add --yes)
  --onboard          Fresh machine wizard (setup → check → rebuild)
  --onboard --skip-setup  Onboard from check step (after ./setup.sh)
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
  ./run.sh --onboard              # guided: setup → check → rebuild
  ./run.sh --check
  ./install.sh research --yes     # or ./run.sh --rebuild --yes
  ./install.sh list               # other profiles (android-re, dev-stack, mobsf, …)
  ./run.sh --profile research --plan

Legacy scripts in ./legacy/ are disabled reference only.
See: docs/GETTING-STARTED.md
Root: ${FEDORA_ROOT}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) fedora_usage; exit 0 ;;
    --version|-V)
      echo "fedora-linux-scripts run.sh 1.7.0"
      exit 0
      ;;
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
    --install)
      shift
      menu_set_header_fn fedora_main_header
      theme_set_lane main
      MENU_PARENT_CONTEXT="main-menu"
      fedora_install_menu
      exit 0
      ;;
    --onboard)
      shift
      _fedora_run_onboard "$@"
      exit $?
      ;;
    --profile)
      shift
      [[ -n "${1:-}" ]] || die "--profile requires a name (try: ./run.sh --list-profiles)"
      exec bash "${FEDORA_ROOT}/install.sh" "$@"
      ;;
    --list-profiles)
      shift
      exec bash "${FEDORA_ROOT}/install.sh" list "$@"
      ;;
    --workstation)
      shift
      exec bash "${FEDORA_ROOT}/install.sh" workstation "$@"
      ;;
    --rebuild) shift; _fedora_run_rebuild "$@"; exit $? ;;
    --rebuild-yes) shift; _fedora_run_rebuild --yes "$@"; exit $? ;;
    --dry-run) shift; _fedora_run_rebuild --dry-run "$@"; exit $? ;;
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
  theme_meta_line "[1] update · [2] daily sync · ./run.sh --help for CLI"
}

_fedora_install_header() {
  menu_clear_screen
  theme_rule '═'
  if theme_use_color; then
    printf '%s▣ Install workstation%s\n' "${THEME_TITLE}" "${THEME_RESET}"
  else
    printf '▣ Install workstation\n'
  fi
  theme_meta_line "developer tools · desktop · containers · web · Android RE"
  theme_meta_line "Path: $(menu_path_text)"
  menu_hr
  theme_page_title "Install workstation"
  theme_meta_line "pick an area — profiles [6–8] · rebuild [9]"
}

_fedora_install_items() {
  theme_section "Core workstation"
  menu_item_lane 1 dev "Developer tools" "git · vscode · shell helpers"
  menu_item_lane 2 desktop "Desktop environments" "cinnamon · kde · mate · lxqt"
  menu_item_lane 3 virt "Virtualization & containers" "podman · docker · kvm · virtualbox"
  menu_item_lane 4 web "Web/database stack" "apache · mariadb · php · phpmyadmin"
  theme_section "Security research"
  menu_item_lane 5 android "Android RE tools" "sdk · adb · jadx · apktool"
  theme_section "One-command profiles"
  menu_item_lane 6 profile "Workstation profile" "update · git · VS Code · KVM"
  menu_item_lane 7 profile "Research profile" "update · Android RE · optional MobSF"
  menu_item_lane 8 profile "All install profiles" "full catalog · mobsf · web-stack · …"
  theme_section "All-in-one"
  menu_item_lane 9 rebuild "Guided rebuild" "same as research · confirm each step"
  menu_item_back
}

_fedora_install_dispatch() {
  case "$1" in
    0) return 1 ;;
    1) _fedora_inline_menu dev_menu_developer_header dev dev_menu_developer_tools; return 0 ;;
    2) _fedora_inline_menu dev_menu_desktop_header dev dev_menu_desktop_environments; return 0 ;;
    3) _fedora_inline_menu dev_menu_virtualization_header dev dev_menu_infrastructure; return 0 ;;
    4) _fedora_inline_menu dev_menu_web_header dev dev_menu_web_stack; return 0 ;;
    5) _fedora_inline_menu android_menu_main_header android android_main_menu; return 0 ;;
    6) FEDORA_FROM_MENU=1 bash "${FEDORA_ROOT}/install.sh" workstation || true; menu_pause; return 0 ;;
    7) FEDORA_FROM_MENU=1 bash "${FEDORA_ROOT}/install.sh" research || true; menu_pause; return 0 ;;
    8) bash "${FEDORA_ROOT}/install.sh" || true; menu_pause; return 0 ;;
    9)
      info "Guided rebuild (confirm each step)"
      FEDORA_FROM_MENU=1 _fedora_run_rebuild || true
      menu_pause
      return 0
      ;;
    *) return 2 ;;
  esac
}

fedora_install_menu() {
  local prev_header="${MENU_HEADER_FN}"
  menu_set_header_fn _fedora_install_header
  theme_set_lane dev
  menu_loop "Install workstation" "components · guided rebuild" \
    _fedora_install_items _fedora_install_dispatch
  menu_set_header_fn "${prev_header}"
  theme_set_lane main
}

_fedora_main_items() {
  theme_section "Everyday — start here"
  menu_item_lane 1 update "Update Fedora" "sudo · dnf upgrade · full verify · log saved"
  menu_item_lane 2 postupdate "Update + post-update check" "recommended daily workflow"
  menu_item_lane 3 postupdate "Post-update check only" "after manual dnf upgrade"
  theme_section "Fresh machine / full setup"
  menu_item_lane 4 rebuild "Guided rebuild" "update → KVM → Android → RE tools → doctor"
  menu_item_lane 5 dev "Install workstation components" "dev · desktop · virt · web · Android"
  theme_section "Maintenance and health"
  menu_item_lane 6 system "System maintenance" "logs · cleanup · disk · hardening"
  menu_item_lane 7 audit "System health check" "Fedora doctor · repos · lane entry points"
  menu_item_lane 8 check "Toolkit self-test" "validate · smoke · rebuild readiness"
  echo
  menu_item_exit
}

_fedora_main_dispatch() {
  case "$1" in
    0) info "Main menu closed. Run ./run.sh to return."; exit 0 ;;
    1) system_menu_run_update 0; menu_pause; return 0 ;;
    2) system_menu_run_daily_sync 0; menu_pause; return 0 ;;
    3) menu_run_script_scroll system/post_update_check.sh; menu_pause; return 0 ;;
    4)
      info "Guided rebuild (confirm each step)"
      FEDORA_FROM_MENU=1 _fedora_run_rebuild || true
      menu_pause
      return 0
      ;;
    5)
      fedora_install_menu
      return 0
      ;;
    6) _fedora_inline_menu system_menu_header system system_main_menu; return 0 ;;
    7)
      menu_run_script_scroll system/research_doctor.sh --android-only
      menu_pause
      return 0
      ;;
    8)
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
