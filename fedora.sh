#!/usr/bin/env bash
# fedora.sh — Fedora toolkit main entry (lane picker + rebuild + doctor CLI)
# Version: 0.9.1
#
# Run: ./fedora.sh [--help|--check|--smoke|--doctor|--baseline|--rebuild-check|--rebuild*|--system|--dev|--android]
#
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

_fedora_open_lane() {
  local lane="$1"
  local ec=0
  case "${lane}" in
    1) FEDORA_FROM_PICKER=1 bash "${FEDORA_ROOT}/system/system.sh" || ec=$? ;;
    2) FEDORA_FROM_PICKER=1 bash "${FEDORA_ROOT}/dev/dev.sh" || ec=$? ;;
    3) FEDORA_FROM_PICKER=1 bash "${FEDORA_ROOT}/android/android.sh" || ec=$? ;;
    *) die "Invalid lane: ${lane} (use 1–3)" ;;
  esac
  if (( ec != 0 )); then
    warn "Lane exited with status ${ec} — returning to main menu"
  fi
}

# Non-interactive lane shortcut (must run before option parsing consumes args)
if [[ $# -eq 1 ]] && [[ "$1" =~ ^[1-3]$ ]]; then
  _fedora_open_lane "$1"
  exit 0
fi

fedora_usage() {
  cat <<EOF
Fedora Workstation Toolkit — main entry point.

Quick start:
  ./fedora.sh
  ./fedora.sh --check          All-in-one readiness (validate · smoke · rebuild)
  ./fedora.sh --check --full   Include full smoke + Fedora doctor
  ./fedora.sh --check --fix-repos   Fix DNF repos (sudo) then re-check
  ./fedora.sh --doctor
  ./fedora.sh --baseline
  ./fedora.sh --rebuild-check
  ./fedora.sh --rebuild
  ./fedora.sh --smoke          Dynamic CLI/menu tests

MobSF stack (separate lifecycle):
  ./mobsf.sh
  ./mobsf.sh --doctor

Usage: $(basename "$0") [options|lane]

Lane (non-interactive):
  1|2|3              Open System / Development / Android RE once, then exit

Options:
  --help, -h         Show this help
  --no-color         Plain text output (also: NO_COLOR=1)
  --check            Validate + smoke + rebuild readiness (add --full or --fix-repos)
  --smoke          Run ./smoke_test.sh --quick (append --full for full doctors)
  --fix-repos        Fix DNF .repo permissions (sudo — common rebuild-check fix)
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
  --system           Open System lane menu
  --dev              Open Development lane menu
  --android          Open Android RE lane menu

Lane launchers:
  ./system/system.sh       Host · updates · logs · cleanup
  ./dev/dev.sh             Git · VS Code · KVM · LAMP
  ./android/android.sh     Android RE workstation

Fresh install flow:
  ./fedora.sh --check
  ./fedora.sh --doctor
  ./fedora.sh --rebuild

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
    --doctor) shift; exec bash "${FEDORA_ROOT}/system/research_doctor.sh" --android-only "$@" ;;
    --baseline) shift; exec bash "${FEDORA_ROOT}/system/fresh_install_check.sh" "$@" ;;
    --security-audit) shift; exec bash "${FEDORA_ROOT}/system/security_audit.sh" "$@" ;;
    --audit-summary) shift; exec bash "${FEDORA_ROOT}/system/security_audit.sh" --summary "$@" ;;
    --audit-plan) shift; exec bash "${FEDORA_ROOT}/system/security_audit.sh" --plan "$@" ;;
    --host-context) shift; exec bash "${FEDORA_ROOT}/system/host_context.sh" "$@" ;;
    --rebuild-check) shift; exec bash "${FEDORA_ROOT}/system/rebuild_readiness_check.sh" "$@" ;;
    --system) shift; FEDORA_FROM_PICKER=1 exec bash "${FEDORA_ROOT}/system/system.sh" "$@" ;;
    --dev) shift; FEDORA_FROM_PICKER=1 exec bash "${FEDORA_ROOT}/dev/dev.sh" "$@" ;;
    --android) shift; FEDORA_FROM_PICKER=1 exec bash "${FEDORA_ROOT}/android/android.sh" "$@" ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

fedora_main_header() {
  menu_clear_screen
  theme_banner "${MENU_APP_NAME}"
  theme_meta_line "Host: $(hostname) · User: $(real_user)"
  theme_meta_line "Root: ${MENU_ROOT}"
}

_fedora_main_items() {
  theme_section "Main lanes"
  menu_item 1 "System" "host · updates · logs · cleanup"
  menu_item 2 "Development" "git · vscode · kvm · lamp"
  menu_item 3 "Android RE" "sdk · apktool · jadx · frida · verify"
  theme_section "Setup and health"
  menu_item 4 "Guided rebuild" "full workstation setup"
  menu_item 5 "Fedora doctor" "repo · lanes · workstation health"
  menu_item 6 "Toolkit check" "validate · smoke · rebuild readiness"
  theme_section "Separate tools"
  theme_note_kv "MobSF stack" "./mobsf.sh"
  theme_section "Shortcuts"
  theme_shortcut "r" "repeat menu"
  echo
  menu_item_exit
}

_fedora_main_dispatch() {
  case "$1" in
    0) info "Main menu closed. Run ./fedora.sh to return."; exit 0 ;;
    1|2|3) _fedora_open_lane "$1"; return 0 ;;
    4)
      info "Guided rebuild (confirm each step)"
      FEDORA_FROM_MENU=1 FEDORA_REBUILD_VIA_FEDORA=1 bash "${FEDORA_ROOT}/fedora_rebuild.sh" || true
      menu_pause
      return 0
      ;;
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
  menu_set_header_fn fedora_main_header
  menu_loop "Main menu" "" _fedora_main_items _fedora_main_dispatch
}

main_menu
