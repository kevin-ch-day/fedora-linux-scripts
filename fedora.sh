#!/usr/bin/env bash
# fedora.sh — Fedora toolkit lane picker (launches lane menus, returns here on exit)
# Version: 0.5.5
#
# Run: ./fedora.sh [--help|--doctor|--rebuild*]
#
# This script picks a lane and opens its menu. When you exit a lane, you return
# here. Full rebuild: ./fedora_rebuild.sh (separate script).

set -euo pipefail

FEDORA_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/menu.sh
source "${FEDORA_ROOT}/lib/menu.sh"

menu_init "Fedora Toolkit" "${FEDORA_ROOT}"

_fedora_open_lane() {
  local lane="$1"
  local ec=0
  case "${lane}" in
    1) FEDORA_FROM_PICKER=1 bash "${FEDORA_ROOT}/system/system.sh" || ec=$? ;;
    2) FEDORA_FROM_PICKER=1 bash "${FEDORA_ROOT}/dev/dev.sh" || ec=$? ;;
    3) FEDORA_FROM_PICKER=1 bash "${FEDORA_ROOT}/android/android.sh" || ec=$? ;;
    4) FEDORA_FROM_PICKER=1 bash "${FEDORA_ROOT}/mobsf/mobsf.sh" || ec=$? ;;
    *) die "Invalid lane: ${lane} (use 1–4)" ;;
  esac
  if (( ec != 0 )); then
    warn "Lane exited with status ${ec} — returning to lane picker"
  fi
}

# Non-interactive lane shortcut (must run before option parsing consumes args)
if [[ $# -eq 1 ]] && [[ "$1" =~ ^[1-4]$ ]]; then
  _fedora_open_lane "$1"
  exit 0
fi

fedora_usage() {
  cat <<EOF
Fedora toolkit — pick a lane (exit a lane to return here).

Usage: $(basename "$0") [options|lane]

Lane (non-interactive):
  1|2|3|4          Open System / Dev / Android / MobSF lane once, then exit to shell

Menu keys (interactive):
  [0] Back one level   [r] Repeat last choice

Options:
  --help, -h       Show this help
  --doctor         Full research doctor (Android + MobSF)
  --rebuild        Run guided rebuild (same as ./fedora_rebuild.sh)
  --rebuild-yes    Rebuild with --yes
  --dry-run        Rebuild dry-run

Lane launchers (same as the interactive menu):
  ./system/system.sh       Host, update, logs, research doctor
  ./dev/dev.sh             Git, VS Code, KVM, LAMP
  ./android/android.sh     Android RE workstation
  ./mobsf/mobsf.sh         MobSF static analysis

Guided full rebuild (separate script — not a submenu here):
  ./fedora_rebuild.sh              Confirm each step
  ./fedora_rebuild.sh --yes        Unattended core steps
  ./fedora_rebuild.sh --dry-run    Show plan only

fedora.sh          = daily work — lanes [1–4], rebuild [5], doctor (--doctor)
fedora_rebuild.sh  = same as picker [5] with optional mode menu first

Legacy scripts in ./legacy/ are disabled reference only (not in this menu).
See: GETTING-STARTED.md
Root: ${FEDORA_ROOT}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) fedora_usage; exit 0 ;;
    --rebuild) exec bash "${FEDORA_ROOT}/fedora_rebuild.sh" ;;
    --rebuild-yes) exec bash "${FEDORA_ROOT}/fedora_rebuild.sh" --yes ;;
    --dry-run) exec bash "${FEDORA_ROOT}/fedora_rebuild.sh" --dry-run ;;
    --doctor) exec bash "${FEDORA_ROOT}/system/research_doctor.sh" ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

_fedora_main_items() {
  menu_item 1 "System lane      (host · update · logs)"
  menu_item 2 "Dev lane         (git · KVM · LAMP)"
  menu_item 3 "Android RE lane  (SDK · RE tools · verify)"
  menu_item 4 "MobSF lane       (static analysis stack)"
  menu_item 5 "Guided rebuild   (full workstation setup)"
  menu_item_exit
}

_fedora_main_dispatch() {
  case "$1" in
    0) echo "Bye."; exit 0 ;;
    1|2|3|4) _fedora_open_lane "$1"; return 0 ;;
    5)
      info "Leaving lane picker — guided rebuild (confirm each step)"
      FEDORA_FROM_MENU=1 bash "${FEDORA_ROOT}/fedora_rebuild.sh" || true
      menu_pause
      return 0
      ;;
    *) return 2 ;;
  esac
}

main_menu() {
  menu_loop "Lane picker" \
    "rebuild: [5] or ./fedora_rebuild.sh  ·  doctor: ./fedora.sh --doctor  ·  [r] repeat" \
    _fedora_main_items _fedora_main_dispatch
}

main_menu
