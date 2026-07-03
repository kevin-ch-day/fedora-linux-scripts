#!/usr/bin/env bash
# install.sh — profile-based workstation install launcher
# Version: 0.2.0
#
# Run:
#   ./install.sh list
#   ./install.sh research [--yes] [--dry-run] [--log] [--plan]
#   ./install.sh                    # interactive profile picker

set -euo pipefail

FEDORA_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${FEDORA_ROOT}/lib/common.sh"
# shellcheck source=lib/theme.sh
source "${FEDORA_ROOT}/lib/theme.sh"
theme_init
# shellcheck source=lib/menu.sh
source "${FEDORA_ROOT}/lib/menu.sh"
# shellcheck source=lib/install_engine.sh
source "${FEDORA_ROOT}/lib/install_engine.sh"

PROFILE=""
AUTO_YES=0
DRY_RUN=0
USE_LOG=0
LIST_ONLY=0
PLAN_ONLY=0
VALIDATE_ONLY=0

_PROFILE_IDS=(
  research android-re dev-stack dev-full web-stack mobsf daily-sync update-only
)

usage() {
  cat <<EOF
Usage: $(basename "$0") [profile] [options]

Run a named install profile (see: ./install.sh list).

Profiles:
  research      Full research workstation (same as ./run.sh --rebuild)
  android-re    Android RE tools only
  dev-stack     VS Code + containers/KVM
  dev-full      Git (if needed) + VS Code + containers/KVM
  web-stack     Apache · MariaDB · PHP · phpMyAdmin
  mobsf         MobSF Podman stack install + doctor
  workstation   Daily sync + dev-full (update · git · VS Code · KVM)
  daily-sync    Full update + post-update check
  update-only   Fedora update only

Options:
  list           Print profile catalog and exit
  --yes, -y      Auto-run all steps (no prompts)
  --dry-run      Show steps only (execute nothing)
  --plan         Print numbered step plan (no execution)
  --validate     Verify profile step scripts exist, then exit
  --log          Tee output to logs/fedora_rebuild.log
  --help, -h     Show this help

Examples:
  ./install.sh research --plan
  ./install.sh research --yes
  ./install.sh dev-full --yes
  ./run.sh --profile mobsf --dry-run

Root: ${FEDORA_ROOT}
EOF
}

install_profile_menu() {
  menu_init "Install profiles" "${FEDORA_ROOT}"

  _install_profile_items() {
    local n=1 p desc
    theme_section "Profiles"
    for p in $(profile_list_names); do
      desc="$(profile_description "${p}")"
      menu_item "${n}" "${p} — ${desc}"
      n=$((n + 1))
    done
    menu_item 0 "Back / cancel"
  }

  _install_profile_dispatch() {
    local choice="$1" n=1 p
    (( choice == 0 )) && return 1
    for p in $(profile_list_names); do
      if (( choice == n )); then
        PROFILE="${p}"
        if (( PLAN_ONLY )); then
          install_engine_run_profile "${FEDORA_ROOT}" "${PROFILE}" 0 0 0 1 1
        else
          install_engine_run_profile "${FEDORA_ROOT}" "${PROFILE}" "${AUTO_YES}" "${DRY_RUN}" "${USE_LOG}" 1 0
        fi
        menu_pause
        return 0
      fi
      n=$((n + 1))
    done
    return 2
  }

  menu_loop "Choose install profile" "./install.sh <profile> [--yes]" \
    _install_profile_items _install_profile_dispatch
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    list) LIST_ONLY=1; shift ;;
    --yes|-y) AUTO_YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --plan) PLAN_ONLY=1; shift ;;
    --validate) VALIDATE_ONLY=1; shift ;;
    --log) USE_LOG=1; shift ;;
    research|android-re|dev-stack|dev-full|web-stack|mobsf|workstation|daily-sync|update-only)
      PROFILE="$1"
      shift
      ;;
    *)
      die "Unknown argument: $1 (try: ./install.sh list)"
      ;;
  esac
done

if (( LIST_ONLY )); then
  profile_print_catalog
  exit 0
fi

if [[ -z "${PROFILE}" ]]; then
  if [[ -t 0 && -t 1 ]]; then
    install_profile_menu
    exit 0
  fi
  die "Profile required in non-interactive mode (try: ./install.sh list)"
fi

if (( VALIDATE_ONLY )); then
  if install_engine_validate_profile "${FEDORA_ROOT}" "${PROFILE}"; then
    ok "Profile '${PROFILE}' — all step scripts present"
    exit 0
  fi
  err "Profile '${PROFILE}' validation failed"
  exit 1
fi

install_engine_run_profile "${FEDORA_ROOT}" "${PROFILE}" "${AUTO_YES}" "${DRY_RUN}" "${USE_LOG}" "${FEDORA_FROM_MENU:-0}" "${PLAN_ONLY}"
