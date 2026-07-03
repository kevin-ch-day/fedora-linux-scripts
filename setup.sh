#!/usr/bin/env bash
# setup.sh — lightweight repo/toolkit readiness (no installs, no sudo)
# Version: 0.2.0
#
# Run:
#   ./setup.sh
#   ./setup.sh --smoke
#   ./setup.sh --guided   # validate then offer ./run.sh --onboard --skip-setup

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT}/lib/common.sh"
# shellcheck source=lib/theme.sh
source "${ROOT}/lib/theme.sh"
theme_init
theme_set_lane audit

RUN_SMOKE=0
GUIDED=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Lightweight repo readiness for the Fedora workstation toolkit.
Does not install packages or change system state.

Options:
  --help, -h   Show this help
  --smoke      Also run ./smoke_test.sh --quick after validate
  --guided     After validate, continue with onboard wizard (check → rebuild)

Default:
  Ensure root entry scripts are executable
  Run ./validate.sh --quick
  Print next steps (./run.sh --daily-driver-check, ./run.sh --check)

Toolkit root: ${ROOT}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --smoke) RUN_SMOKE=1; shift ;;
    --guided) GUIDED=1; shift ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

theme_lane_banner "Fedora toolkit setup" audit
theme_meta_line "Root: ${ROOT}"
theme_meta_line "Read-only · no sudo · no package installs"
theme_rule '─'
echo

theme_section "Entry script permissions"
for script in run.sh install.sh setup.sh mobsf.sh validate.sh smoke_test.sh; do
  path="${ROOT}/${script}"
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
for script in fedora.sh fedora_rebuild.sh; do
  path="${ROOT}/${script}"
  if [[ -x "${path}" ]]; then
    ok "${script}: legacy redirect OK"
  elif [[ -f "${path}" ]]; then
    chmod +x "${path}"
    ok "${script}: legacy redirect (made executable)"
  else
    theme_note "${script}: optional legacy redirect missing"
  fi
done

theme_section "Repo validation"
if bash "${ROOT}/validate.sh" --quick; then
  val_ec=0
else
  val_ec=$?
fi

if (( RUN_SMOKE )); then
  echo
  theme_section "Smoke tests"
  if bash "${ROOT}/smoke_test.sh" --quick; then
    smoke_ec=0
  else
    smoke_ec=$?
  fi
else
  smoke_ec=0
fi

echo
if (( val_ec == 0 && smoke_ec == 0 )); then
  if (( GUIDED )); then
    # shellcheck source=lib/workflows.sh
    source "${ROOT}/lib/workflows.sh"
    workflow_onboard_fresh_machine "${ROOT}" 1
    exit $?
  fi
  theme_summary_box "Setup complete" \
    "Result:     OK" \
    "Next:       ./run.sh" \
    "            ./run.sh --daily" \
    "            ./install.sh list"
  exit 0
fi

theme_summary_box "Setup complete" \
  "Result:     REVIEW" \
  "Next:       fix validation/smoke issues above" \
  "            then ./run.sh --check"
exit 1
