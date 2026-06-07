#!/usr/bin/env bash
# smoke_test.sh — dynamic CLI smoke tests (read-only, no sudo prompts)
# Version: 0.2.2
#
# Run from repo root:
#   ./smoke_test.sh
#   ./smoke_test.sh --quick     # skip slower doctor runs
#   NO_COLOR=1 ./smoke_test.sh
#
# When invoked from ./fedora.sh --check, FEDORA_SKIP_CHECK_SMOKE=1 avoids
# re-entering --check (prevents recursion).
#
# Also: ./validate.sh --smoke

set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT}/lib/common.sh"
# shellcheck source=lib/theme.sh
source "${ROOT}/lib/theme.sh"
theme_init

QUICK=0
CI=0
RUNS=0
FAILS=0
declare -a FAIL_NAMES=()

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Dynamic smoke tests for the Fedora toolkit (no installs, no sudo).

Options:
  --quick    Skip full doctor runs (faster)
  --ci       GitHub Actions / non-Fedora host (skip host-specific checks)
  --help,-h  Show this help

Typical flow on a new machine:
  ./fedora.sh --check
  ./fedora.sh --doctor
  ./fedora.sh --rebuild
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --quick) QUICK=1; shift ;;
    --ci) CI=1; QUICK=1; shift ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

_smoke_run() {
  local name="$1"
  local expect_ec="$2"
  shift 2
  local out ec
  RUNS=$((RUNS + 1))
  if out="$("$@" 2>&1)"; then
    ec=0
  else
    ec=$?
  fi
  if [[ "${ec}" -eq "${expect_ec}" ]]; then
    ok "${name} (exit ${ec})"
    return 0
  fi
  FAILS=$((FAILS + 1))
  FAIL_NAMES+=("${name} (expected exit ${expect_ec}, got ${ec})")
  warn "${name} — expected exit ${expect_ec}, got ${ec}"
  printf '%s\n' "${out}" | tail -n 4 | sed 's/^/    /'
  return 1
}

_smoke_menu() {
  local name="$1"
  local script="$2"
  local input="${3:-0\\n}"
  local from_picker="${4:-0}"
  RUNS=$((RUNS + 1))
  local out ec
  if (( from_picker )); then
    if out="$(printf '%b' "${input}" | NO_COLOR=1 FEDORA_FROM_PICKER=1 bash "${script}" 2>&1)"; then
      ec=0
    else
      ec=$?
    fi
  elif out="$(printf '%b' "${input}" | NO_COLOR=1 bash "${script}" 2>&1)"; then
    ec=0
  else
    ec=$?
  fi
  if [[ "${ec}" -eq 0 ]] && grep -qE 'Choice:|Back to lane picker|Main menu closed|MobSF menu closed|Returned to shell' <<< "${out}"; then
    ok "${name} (interactive menu OK)"
    return 0
  fi
  FAILS=$((FAILS + 1))
  FAIL_NAMES+=("${name} (menu smoke failed)")
  warn "${name} — menu smoke failed (exit ${ec})"
  printf '%s\n' "${out}" | tail -n 6 | sed 's/^/    /'
  return 1
}

# Accept exit 0 or 1 when output includes expected summary marker (host-dependent checks).
_smoke_run_summary() {
  local name="$1"
  local marker="$2"
  shift 2
  local out ec
  RUNS=$((RUNS + 1))
  if out="$("$@" 2>&1)"; then
    ec=0
  else
    ec=$?
  fi
  if [[ "${ec}" -le 1 ]] && grep -q "${marker}" <<< "${out}"; then
    ok "${name} (exit ${ec}, summary OK)"
    return 0
  fi
  FAILS=$((FAILS + 1))
  FAIL_NAMES+=("${name} (expected summary with exit 0–1, got ${ec})")
  warn "${name} — expected summary marker, got exit ${ec}"
  printf '%s\n' "${out}" | tail -n 6 | sed 's/^/    /'
  return 1
}

theme_init
theme_set_lane audit

theme_lane_banner "Fedora toolkit smoke tests" audit
theme_meta_line "Root: ${ROOT}"
if (( CI )); then
  theme_meta_line "Mode: CI (host-specific checks skipped)"
elif (( QUICK )); then
  theme_meta_line "Mode: quick (doctors skipped)"
else
  theme_meta_line "Mode: full"
fi
theme_rule '─'
echo

theme_report_section "Help and CLI dispatch"
_smoke_run "fedora.sh --help" 0 bash "${ROOT}/fedora.sh" --help
_smoke_run "fedora.sh --check bad option" 1 bash "${ROOT}/fedora.sh" --check --not-a-flag
_smoke_run "system.sh --help" 0 bash "${ROOT}/system/system.sh" --help
if (( CI == 0 )); then
  _smoke_run "system.sh doctor" 0 bash "${ROOT}/system/system.sh" doctor
fi
_smoke_run "fedora.sh unknown option" 1 bash "${ROOT}/fedora.sh" --not-a-flag
if (( CI == 0 )); then
  _smoke_run "fedora.sh --baseline" 0 bash "${ROOT}/fedora.sh" --baseline
  _smoke_run_summary "security_audit --plan" "Recommended action plan" \
    bash "${ROOT}/system/security_audit.sh" --plan
  _smoke_run_summary "security_audit --findings" "Smart findings" \
    bash "${ROOT}/system/security_audit.sh" --findings
  _smoke_run "host_context.sh" 0 bash "${ROOT}/system/host_context.sh" --summary </dev/null
fi

if (( CI == 0 )) && [[ -z "${FEDORA_SKIP_CHECK_SMOKE:-}" ]]; then
  theme_report_section "Readiness checks"
  _smoke_run "fedora.sh --rebuild-check" 1 bash "${ROOT}/fedora.sh" --rebuild-check
  _smoke_run_summary "fedora.sh --check" "Check complete" bash "${ROOT}/fedora.sh" --check
fi

if (( QUICK == 0 && CI == 0 )); then
  theme_report_section "Doctor runs"
  _smoke_run "fedora.sh --doctor" 0 bash "${ROOT}/fedora.sh" --doctor
  _smoke_run "android.sh --doctor" 0 bash "${ROOT}/android/android.sh" --doctor
  _smoke_run "mobsf.sh --doctor" 1 bash "${ROOT}/mobsf.sh" --doctor
else
  theme_report_section "Doctors skipped (--quick)"
fi

if (( CI )); then
  theme_note "Host-specific checks skipped (--ci)"
fi

theme_report_section "CLI arg passthrough and errors"
_smoke_run "system.sh update --help" 0 bash "${ROOT}/system/system.sh" update --help
_smoke_run "dev.sh git --help" 0 bash "${ROOT}/dev/dev.sh" git --help
_smoke_run "dev.sh git non-interactive" 1 bash "${ROOT}/dev/dev.sh" git </dev/null
_smoke_run "android verify missing tool" 1 bash "${ROOT}/android/android.sh" verify
_smoke_run "log_engine unknown command" 2 bash "${ROOT}/system/log_engine.sh" bogus
_smoke_run "mobsf.sh unknown option" 1 bash "${ROOT}/mobsf.sh" --not-a-flag

theme_report_section "Verify and validate"
if (( CI == 0 )); then
  _smoke_run "android verify all" 0 bash "${ROOT}/android/android.sh" verify all
fi
_smoke_run "validate.sh --quick --install-audit" 0 bash "${ROOT}/validate.sh" --quick --install-audit

theme_report_section "Interactive menus (non-interactive input)"
_smoke_menu "fedora.sh main menu" "${ROOT}/fedora.sh" '0\n'
_smoke_menu "system.sh from picker" "${ROOT}/system/system.sh" '0\n' 1
_smoke_menu "dev.sh from picker" "${ROOT}/dev/dev.sh" '0\n' 1
_smoke_menu "android.sh from picker" "${ROOT}/android/android.sh" '0\n' 1
_smoke_menu "mobsf.sh main menu" "${ROOT}/mobsf.sh" '0\n'

echo
if (( FAILS == 0 )); then
  theme_summary_box "Smoke test summary" \
    "Result:  PASSED" \
    "Runs:    ${RUNS}" \
    "Failed:  0" \
    "Next:    ./fedora.sh --check  or  ./fedora.sh --doctor"
  exit 0
fi

theme_summary_box "Smoke test summary" \
  "Result: FAILED" \
  "Runs: ${RUNS}" \
  "Failed: ${FAILS}" \
  "Next: review failed checks below"
theme_fail_list "${FAIL_NAMES[@]}"
exit 1
