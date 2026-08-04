#!/usr/bin/env bash
# setup.sh — Fedora workstation bootstrap and profile setup
#
# The normal first command after cloning this repository. It validates the
# checkout before offering (or running) an explicitly selected install profile.

set -euo pipefail

FEDORA_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${FEDORA_ROOT}/lib/common.sh"
# shellcheck source=lib/theme.sh
source "${FEDORA_ROOT}/lib/theme.sh"
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
ALLOW_SERVICE_START=0
RUN_SMOKE=0
GUIDED=0
CHECK_ONLY=0

usage() {
  cat <<EOF
Usage: ./setup.sh [profile] [options]

Bootstrap a freshly cloned Fedora workstation checkout, then choose or run a
named setup profile. Run without arguments for the interactive first-run flow.

Profiles:
  research      Full research workstation (same as ./run.sh --rebuild)
  android-re    Android RE tools only
  dev-stack     VS Code + containers/KVM
  dev-full      Git (if needed) + VS Code + containers/KVM
  web-stack     Apache · MariaDB · PHP · phpMyAdmin
  mariadb-no-start  MariaDB packages only; service remains untouched
  mobsf         MobSF Podman stack install + doctor
  workstation   Daily sync + dev-full
  daily-sync    Full update + post-update check
  update-only   Fedora update only

Options:
  list           Print profile catalog and exit
  --check         Validate this checkout only; no installs
  --smoke         Include dynamic smoke tests in the bootstrap check
  --guided        Validate, then enter the guided onboard workflow
  --yes, -y       Auto-run all selected profile steps (no prompts)
  --dry-run       Show selected profile steps only
  --plan          Print a selected profile's numbered plan only
  --validate      Verify selected profile scripts exist, then exit
  --log           Tee selected profile output to logs/fedora_rebuild.log
  --allow-service-start
                 Required with --yes for service-enabling profiles
  --help, -h      Show this help

Examples:
  ./setup.sh                         # first clone: check, then choose a profile
  ./setup.sh --check                 # repository readiness only
  ./setup.sh research --plan         # review the full setup before mutation
  ./setup.sh research --yes          # run full research setup
  ./setup.sh dev-full --dry-run --yes

Day-to-day use after setup: ./run.sh
MobSF remains separate: ./mobsf.sh
EOF
}

setup_profile_menu() {
  menu_init "Fedora Workstation Setup" "${FEDORA_ROOT}"

  _setup_profile_items() {
    local n=1 p desc
    theme_section "Setup profiles"
    for p in $(profile_list_names); do
      desc="$(profile_description "${p}")"
      menu_item "${n}" "${p} — ${desc}"
      n=$((n + 1))
    done
    menu_item 0 "Back / finish bootstrap"
  }

  _setup_profile_dispatch() {
    local choice="$1" n=1 p
    (( choice == 0 )) && return 1
    for p in $(profile_list_names); do
      if (( choice == n )); then
        PROFILE="${p}"
        install_engine_run_profile "${FEDORA_ROOT}" "${PROFILE}" \
          "${AUTO_YES}" "${DRY_RUN}" "${USE_LOG}" 1 "${PLAN_ONLY}"
        menu_pause
        return 0
      fi
      n=$((n + 1))
    done
    return 2
  }

  menu_loop "Choose setup profile" "./setup.sh <profile> [--yes]" \
    _setup_profile_items _setup_profile_dispatch
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --check) CHECK_ONLY=1; shift ;;
    --smoke) RUN_SMOKE=1; shift ;;
    --guided) GUIDED=1; shift ;;
    list) LIST_ONLY=1; shift ;;
    --yes|-y) AUTO_YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --plan) PLAN_ONLY=1; shift ;;
    --validate) VALIDATE_ONLY=1; shift ;;
    --log) USE_LOG=1; shift ;;
    --allow-service-start) ALLOW_SERVICE_START=1; shift ;;
    research|android-re|dev-stack|dev-full|web-stack|mariadb-no-start|mobsf|workstation|daily-sync|update-only)
      PROFILE="$1"; shift ;;
    *) die "Unknown argument: $1 (try: ./setup.sh --help)" ;;
  esac
done

INSTALL_ENGINE_ALLOW_SERVICE_START="${ALLOW_SERVICE_START}"

if (( PLAN_ONLY && VALIDATE_ONLY )); then
  die "--plan and --validate cannot be used together"
fi
if (( RUN_SMOKE && ( LIST_ONLY || PLAN_ONLY || VALIDATE_ONLY ) )); then
  die "--smoke is only available for a bootstrap check, guided setup, or profile run"
fi
if (( CHECK_ONLY && ( LIST_ONLY || PLAN_ONLY || VALIDATE_ONLY || GUIDED || ${#PROFILE} > 0 ) )); then
  die "--check is a repository-only mode; remove the profile or other mode"
fi
if (( GUIDED && ( LIST_ONLY || PLAN_ONLY || VALIDATE_ONLY || ${#PROFILE} > 0 ) )); then
  die "--guided cannot be combined with a profile, list, --plan, or --validate"
fi
if (( LIST_ONLY && ( PLAN_ONLY || VALIDATE_ONLY || ${#PROFILE} > 0 || AUTO_YES || DRY_RUN || USE_LOG || ALLOW_SERVICE_START ) )); then
  die "list cannot be combined with a profile or profile-execution option"
fi

if (( LIST_ONLY )); then
  profile_print_catalog
  exit 0
fi

if (( PLAN_ONLY || VALIDATE_ONLY )); then
  [[ -n "${PROFILE}" ]] || die "A profile is required (try: ./setup.sh list)"
  if (( VALIDATE_ONLY )); then
    if install_engine_validate_profile "${FEDORA_ROOT}" "${PROFILE}"; then
      ok "Profile '${PROFILE}' — all step scripts present"
      exit 0
    fi
    err "Profile '${PROFILE}' validation failed"
    exit 1
  fi
  install_engine_plan_profile "${FEDORA_ROOT}" "${PROFILE}"
  exit 0
fi

theme_init
theme_set_lane audit
theme_lane_banner "Fedora Workstation Setup" audit
theme_meta_line "ROOT / ${FEDORA_ROOT}"
theme_meta_line "Bootstrap check · no sudo · no package installs"
theme_rule '─'
echo

theme_section "Required launchers"
for script in run.sh setup.sh mobsf.sh validate.sh smoke_test.sh; do
  path="${FEDORA_ROOT}/${script}"
  if [[ ! -f "${path}" ]]; then
    warn "Missing: ${script}"
    continue
  fi
  if [[ -x "${path}" ]]; then
    ok "${script}: executable"
  else
    chmod +x "${path}"
    ok "${script}: made executable"
  fi
done

theme_section "Repository validation"
if bash "${FEDORA_ROOT}/validate.sh" --quick; then
  validation_ec=0
else
  validation_ec=$?
fi

if (( RUN_SMOKE )); then
  echo
  theme_section "Smoke tests"
  if bash "${FEDORA_ROOT}/smoke_test.sh" --quick; then
    smoke_ec=0
  else
    smoke_ec=$?
  fi
else
  smoke_ec=0
fi

if (( validation_ec != 0 || smoke_ec != 0 )); then
  echo
  theme_summary_box "Setup check" \
    "Result:     REVIEW" \
    "Next:       fix validation issues above" \
    "            then rerun ./setup.sh --check"
  exit 1
fi

if (( GUIDED )); then
  # shellcheck source=lib/workflows.sh
  source "${FEDORA_ROOT}/lib/workflows.sh"
  workflow_onboard_fresh_machine "${FEDORA_ROOT}" 1
  exit $?
fi

if (( CHECK_ONLY )); then
  theme_summary_box "Setup check complete" \
    "Result:     OK" \
    "Next:       ./setup.sh (choose a setup profile)" \
    "            ./run.sh (day-to-day control)"
  exit 0
fi

if [[ -n "${PROFILE}" ]]; then
  install_engine_run_profile "${FEDORA_ROOT}" "${PROFILE}" \
    "${AUTO_YES}" "${DRY_RUN}" "${USE_LOG}" "${FEDORA_FROM_MENU:-0}" 0
  exit $?
fi

if [[ -t 0 && -t 1 ]]; then
  setup_profile_menu
  exit 0
fi

theme_summary_box "Setup check complete" \
  "Result:     OK" \
  "Next:       ./setup.sh list" \
  "            ./setup.sh research --plan"
