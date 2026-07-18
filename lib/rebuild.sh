#!/usr/bin/env bash
# lib/rebuild.sh — guided rebuild runner (research profile + mode menu)
# Version: 0.1.0
#
# Source after lib/common.sh, lib/menu.sh, lib/install_engine.sh.
# Invoked by: ./run.sh --rebuild  ·  ./install.sh research

if [[ -n "${FEDORA_REBUILD_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_REBUILD_SH_LOADED=1

_REBUILD_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_REBUILD_LIB_DIR}/common.sh"
# shellcheck source=theme.sh
source "${_REBUILD_LIB_DIR}/theme.sh"
# shellcheck source=logging.sh
source "${_REBUILD_LIB_DIR}/logging.sh"
# shellcheck source=menu.sh
source "${_REBUILD_LIB_DIR}/menu.sh"
# shellcheck source=install_engine.sh
source "${_REBUILD_LIB_DIR}/install_engine.sh"

fedora_rebuild_usage() {
  cat <<EOF
Usage: ./run.sh --rebuild [options]

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
  --plan                 Print profile step plan (no execution)
  --help, -h             Show this help

Profiles: ./install.sh list

With --yes: auto-installs MobSF when compose is missing; runs research doctor at end.

Entry: ./run.sh --rebuild   (preferred — ./fedora_rebuild.sh redirects here)
See: docs/GETTING-STARTED.md
EOF
}

_fedora_rebuild_mode_menu() {
  local root="$1"
  local profile="$2"
  local auto_yes_var="$3"
  local dry_run_var="$4"
  local use_log_var="$5"

  menu_init "Fedora Rebuild" "${root}"

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
      2) printf -v "${auto_yes_var}" '%s' 1; return 0 ;;
      3) printf -v "${dry_run_var}" '%s' 1; return 0 ;;
      4) printf -v "${use_log_var}" '%s' 1; return 0 ;;
      5) printf -v "${auto_yes_var}" '%s' 1; printf -v "${use_log_var}" '%s' 1; return 0 ;;
      *) return 2 ;;
    esac
  }

  menu_loop "Choose rebuild mode" \
    "profile: ${profile} · ./install.sh list for others" \
    _rebuild_mode_items _rebuild_mode_dispatch
}

# fedora_rebuild_run ROOT [args...]
fedora_rebuild_run() {
  local root="${1:?root required}"
  shift

  local auto_yes=0 dry_run=0 use_log=0 plan_only=0
  local profile="${FEDORA_REBUILD_PROFILE:-research}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        profile="${2:?--profile requires a name}"
        shift 2
        ;;
      --yes|-y) auto_yes=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      --log) use_log=1; shift ;;
      --skip-mobsf) FEDORA_SKIP_MOBSF=1; shift ;;
      --skip-doctor|--skip-final-doctor) FEDORA_SKIP_DOCTOR=1; shift ;;
      --plan) plan_only=1; shift ;;
      --help|-h) fedora_rebuild_usage; return 0 ;;
      *) die "Unknown option: $1 (try: ./run.sh --rebuild --help)" ;;
    esac
  done

  profile_is_valid "${profile}" || die "Unknown profile: ${profile} (try: ./install.sh list)"

  if (( plan_only )); then
    install_engine_run_profile "${root}" "${profile}" 0 0 0 0 1
    return 0
  fi

  if (( auto_yes == 0 && dry_run == 0 && use_log == 0 )) && [[ -t 0 ]] && [[ "${FEDORA_FROM_MENU:-}" != 1 ]]; then
    _fedora_rebuild_mode_menu "${root}" "${profile}" auto_yes dry_run use_log
  fi

  if [[ "${FEDORA_FROM_MENU:-}" == 1 ]]; then
    info "Rebuild from run.sh — confirm each step (no mode picker)"
  fi

  theme_note "System updates always log to logs/system_update.log"

  install_engine_run_profile "${root}" "${profile}" "${auto_yes}" "${dry_run}" "${use_log}" "${FEDORA_FROM_MENU:-0}" 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; use: ./run.sh --rebuild"
  exit 1
fi
