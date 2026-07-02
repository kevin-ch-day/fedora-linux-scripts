#!/usr/bin/env bash
# fedora_rebuild.sh — Guided workstation rebuild sequence (implementation)
# Version: 0.5.0
#
# Prefer: ./run.sh --rebuild  ·  ./install.sh research
#
# This script is retained for compatibility. When invoked directly it delegates
# to ./run.sh --rebuild (see FEDORA_REBUILD_VIA_FEDORA guard below).
#
# Run:
#   ./run.sh --rebuild                 # preferred
#   ./install.sh research --yes        # same profile engine
#   ./fedora_rebuild.sh              # compatibility → run.sh --rebuild
#   ./run.sh --rebuild --yes         # no prompts between steps
#   ./run.sh --rebuild --dry-run     # show steps only
#   ./run.sh --rebuild --log         # tee output to logs/fedora_rebuild.log

set -euo pipefail

FEDORA_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Compatibility wrapper: direct callers go through run.sh (avoid loop below).
if [[ "${FEDORA_REBUILD_VIA_FEDORA:-}" != 1 ]]; then
  exec bash "${FEDORA_ROOT}/run.sh" --rebuild "$@"
fi
# shellcheck source=lib/common.sh
source "${FEDORA_ROOT}/lib/common.sh"
# shellcheck source=lib/theme.sh
source "${FEDORA_ROOT}/lib/theme.sh"
theme_init
theme_set_lane rebuild
# shellcheck source=lib/logging.sh
source "${FEDORA_ROOT}/lib/logging.sh"
# shellcheck source=lib/menu.sh
source "${FEDORA_ROOT}/lib/menu.sh"
# shellcheck source=lib/install_engine.sh
source "${FEDORA_ROOT}/lib/install_engine.sh"

AUTO_YES=0
DRY_RUN=0
USE_LOG=0
FEDORA_SKIP_MOBSF=0
FEDORA_SKIP_DOCTOR=0
PROFILE="${FEDORA_REBUILD_PROFILE:-research}"
PLAN_ONLY=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Guided rebuild using the research install profile (system update → KVM →
Android → RE tools → optional MobSF → research doctor).

Equivalent: ./install.sh research [options]

Not included (run from Dev lane after rebuild): git, VS Code, Cinnamon desktop,
LAMP/phpMyAdmin — see docs/GETTING-STARTED.md § After rebuild.

Options:
  --profile NAME         Install profile (default: research)
  --yes, -y              Auto-run all core steps (no step prompts)
  --dry-run              Show steps only
  --log                  Tee orchestrator output to logs/fedora_rebuild.log
  --skip-mobsf           Do not offer/run MobSF install
  --skip-doctor          Skip final research_doctor.sh
  --skip-final-doctor    Alias for --skip-doctor
  --plan                 Print research profile step plan (no execution)
  --help, -h             Show this help

Profiles: ./install.sh list

With --yes: auto-installs MobSF when compose is missing; runs research doctor at end.

Daily lane menus: ./run.sh
Preferred rebuild: ./run.sh --rebuild  (this script: compatibility wrapper + implementation)
See: docs/GETTING-STARTED.md
EOF
}

rebuild_mode_menu() {
  menu_init "Fedora Rebuild" "${FEDORA_ROOT}"

  _rebuild_mode_items() {
    menu_item 1 "Interactive (confirm each step)"
    menu_item 2 "Auto-yes (no prompts between steps)"
    menu_item 3 "Dry run (show steps only)"
    menu_item 4 "Interactive + log to fedora_rebuild.log"
    menu_item 5 "Auto-yes + log"
    menu_item 0 "Cancel"
  }

  _rebuild_mode_dispatch() {
    case "$1" in
      0) echo "Cancelled."; exit 0 ;;
      1) return 0 ;;
      2) AUTO_YES=1; return 0 ;;
      3) DRY_RUN=1; return 0 ;;
      4) USE_LOG=1; return 0 ;;
      5) AUTO_YES=1; USE_LOG=1; return 0 ;;
      *) return 2 ;;
    esac
  }

  menu_loop "Choose rebuild mode" \
    "profile: ${PROFILE} · ./install.sh list for others" \
    _rebuild_mode_items _rebuild_mode_dispatch
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="${2:?--profile requires a name}"
      shift 2
      ;;
    --yes|-y) AUTO_YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --log) USE_LOG=1; shift ;;
    --skip-mobsf) FEDORA_SKIP_MOBSF=1; shift ;;
    --skip-doctor|--skip-final-doctor) FEDORA_SKIP_DOCTOR=1; shift ;;
    --plan) PLAN_ONLY=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

profile_is_valid "${PROFILE}" || die "Unknown profile: ${PROFILE} (try: ./install.sh list)"

if (( PLAN_ONLY )); then
  install_engine_run_profile "${FEDORA_ROOT}" "${PROFILE}" 0 0 0 0 1
  exit 0
fi

if (( AUTO_YES == 0 && DRY_RUN == 0 && USE_LOG == 0 )) && [[ -t 0 ]] && [[ "${FEDORA_FROM_MENU:-}" != 1 ]]; then
  rebuild_mode_menu
fi

if [[ "${FEDORA_FROM_MENU:-}" == 1 ]]; then
  info "Rebuild from run.sh — confirm each step (no mode picker)"
fi

echo "[NOTE] system_update.sh always logs to logs/system_update.log on its own."

install_engine_run_profile "${FEDORA_ROOT}" "${PROFILE}" "${AUTO_YES}" "${DRY_RUN}" "${USE_LOG}" "${FEDORA_FROM_MENU:-0}" 0
