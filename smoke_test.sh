#!/usr/bin/env bash
# smoke_test.sh — dynamic CLI smoke tests (read-only, no sudo prompts)
# Version: 0.5.0
#
# Run from repo root:
#   ./smoke_test.sh
#   ./smoke_test.sh --quick     # skip slower doctor runs
#   NO_COLOR=1 ./smoke_test.sh
#
# When invoked from ./run.sh --check, FEDORA_SKIP_CHECK_SMOKE=1 avoids
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

Dynamic smoke tests for Fedora Workstation Control (no installs, no sudo).

Options:
  --quick    Skip full doctor runs (faster)
  --ci       GitHub Actions / non-Fedora host (skip host-specific checks)
  --help,-h  Show this help

Typical flow on a new machine:
  ./setup.sh
  ./run.sh --check
  ./run.sh --doctor
  ./run.sh --rebuild
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
  if [[ "${ec}" -eq 0 ]] && grep -qE 'Choice(:| ›)|Back to lane picker|Main menu closed|MobSF menu closed|Returned to shell' <<< "${out}"; then
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

theme_lane_banner "Fedora Workstation Control smoke tests" audit
theme_meta_line "ROOT / ${ROOT}"
if (( CI )); then
  theme_meta_line "MODE / CI · host-specific checks skipped"
elif (( QUICK )); then
  theme_meta_line "MODE / quick · doctors skipped"
else
  theme_meta_line "MODE / full"
fi
theme_rule '─'
echo

theme_report_section "Help and CLI dispatch"
_smoke_run "run.sh --help" 0 bash "${ROOT}/run.sh" --help
_smoke_run "inspect.sh --schema-version" 0 bash "${ROOT}/inspect.sh" --schema-version
_smoke_run "run.sh --inspect --format text" 0 \
  bash "${ROOT}/run.sh" --inspect --format text
_smoke_run "inspect regression tests" 0 \
  python3 -m unittest "${ROOT}/tests/test_inspect.py"
_smoke_run "Android core helper regressions" 0 \
  bash "${ROOT}/tests/test_android_core.sh"
_smoke_run "profile safety regressions" 0 \
  bash "${ROOT}/tests/test_profiles.sh"
_smoke_run "health snapshot regressions" 0 \
  bash "${ROOT}/tests/test_health_snapshot.sh"
_smoke_run "install.sh --help" 0 bash "${ROOT}/install.sh" --help
_smoke_run "install.sh list" 0 bash "${ROOT}/install.sh" list
_smoke_run "install.sh research --plan" 0 bash "${ROOT}/install.sh" research --plan
_smoke_run "install.sh research --validate" 0 bash "${ROOT}/install.sh" research --validate
_smoke_run "install.sh workstation --plan" 0 bash "${ROOT}/install.sh" workstation --plan
_smoke_run "install.sh research --dry-run --yes" 0 bash "${ROOT}/install.sh" research --dry-run --yes
_smoke_run "install.sh not-a-profile" 1 bash "${ROOT}/install.sh" not-a-profile --validate
_smoke_run "run.sh --version" 0 bash "${ROOT}/run.sh" --version
_smoke_run "run.sh --list-profiles" 0 bash "${ROOT}/run.sh" --list-profiles
_smoke_run "run.sh --workstation --plan" 0 bash "${ROOT}/run.sh" --workstation --plan
_smoke_run "fedora_rebuild --plan (via run.sh)" 0 bash "${ROOT}/run.sh" --rebuild --plan
_smoke_run "fedora.sh --help (legacy redirect)" 0 bash "${ROOT}/fedora.sh" --help
_smoke_run "fedora_rebuild.sh --plan (legacy redirect)" 0 bash "${ROOT}/fedora_rebuild.sh" --plan
_smoke_run "run.sh --check bad option" 1 bash "${ROOT}/run.sh" --check --not-a-flag
_smoke_run "system.sh --help" 0 bash "${ROOT}/system/system.sh" --help
_smoke_run_summary "android core status completes without sudo" "SDK/PATH" \
  bash "${ROOT}/android/android_dev_core_setup.sh" --status
if (( CI == 0 && QUICK == 0 )); then
  _smoke_run "system.sh doctor" 0 bash "${ROOT}/system/system.sh" doctor
elif (( CI == 0 )); then
  theme_note "Skipping system.sh doctor in quick mode (no sudo)"
fi
_smoke_run "run.sh unknown option" 1 bash "${ROOT}/run.sh" --not-a-flag
if (( CI == 0 && QUICK == 0 )); then
  _smoke_run "run.sh --baseline" 0 bash "${ROOT}/run.sh" --baseline
  _smoke_run_summary "security_audit --plan" "Recommended action plan" \
    bash "${ROOT}/system/security_audit.sh" --plan
  _smoke_run_summary "security_audit --findings" "Smart findings" \
    bash "${ROOT}/system/security_audit.sh" --findings
  _smoke_run "host_context.sh" 0 bash "${ROOT}/system/host_context.sh" --summary </dev/null
elif (( CI == 0 )); then
  theme_note "Skipping baseline/security audit/host context in quick mode"
fi

if (( CI == 0 && QUICK == 0 )) && [[ -z "${FEDORA_SKIP_CHECK_SMOKE:-}" ]]; then
  theme_report_section "Readiness checks"
  _smoke_run_summary "run.sh --rebuild-check" "Next step:" bash "${ROOT}/run.sh" --rebuild-check
  _smoke_run_summary "run.sh --check" "Check complete" bash "${ROOT}/run.sh" --check
elif (( CI == 0 )); then
  theme_report_section "Readiness checks skipped (--quick)"
fi

if (( QUICK == 0 && CI == 0 )); then
  theme_report_section "Doctor runs"
  _smoke_run "run.sh --doctor" 0 bash "${ROOT}/run.sh" --doctor
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
  _smoke_run_summary "android verify all completes" "Android RE tools" \
    bash "${ROOT}/android/android.sh" verify all
fi
_smoke_run "validate.sh --quick --install-audit" 0 bash "${ROOT}/validate.sh" --quick --install-audit

theme_report_section "Update workflow"
RUNS=$((RUNS + 1))
update_quiet_out="$(NO_COLOR=1 FEDORA_UPDATE_TEST_MODE=1 bash "${ROOT}/system/system_update.sh" --quick 2>&1)" || update_quiet_ec=$?
update_quiet_ec="${update_quiet_ec:-0}"
if [[ "${update_quiet_ec}" -eq 0 ]] \
  && ! grep -qE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2}T' <<< "${update_quiet_out}" \
  && ! grep -q 'SESSION START\|SESSION END\|Session-ID' <<< "${update_quiet_out}" \
  && grep -q '\[Status\]' <<< "${update_quiet_out}" \
  && grep -q '^LOG / ' <<< "${update_quiet_out}" \
  && grep -q 'post-update-check' <<< "${update_quiet_out}"; then
  ok "system_update quiet output stays compact"
else
  FAILS=$((FAILS + 1))
  FAIL_NAMES+=("system_update quiet output stays compact")
  warn "system_update quiet output included log noise or missed summary"
  printf '%s\n' "${update_quiet_out}" | tail -n 8 | sed 's/^/    /'
fi
RUNS=$((RUNS + 1))
update_verbose_out="$(NO_COLOR=1 FEDORA_UPDATE_TEST_MODE=1 FEDORA_VERBOSE=1 bash "${ROOT}/system/system_update.sh" --quick 2>&1)" || update_verbose_ec=$?
update_verbose_ec="${update_verbose_ec:-0}"
if [[ "${update_verbose_ec}" -eq 0 ]] && grep -q 'Updating and loading repositories:' <<< "${update_verbose_out}"; then
  ok "system_update verbose mode streams detailed output"
else
  FAILS=$((FAILS + 1))
  FAIL_NAMES+=("system_update verbose mode streams detailed output")
  warn "system_update verbose mode did not show detailed output"
fi
RUNS=$((RUNS + 1))
update_log_path="${ROOT}/logs/system_update.log"
if [[ -f "${update_log_path}" ]] \
  && grep -q 'SESSION START' "${update_log_path}" \
  && grep -q 'Updating and loading repositories:' "${update_log_path}"; then
  ok "system_update log keeps full detail"
else
  FAILS=$((FAILS + 1))
  FAIL_NAMES+=("system_update log keeps full detail")
  warn "system_update log missing session metadata or detailed output"
fi

theme_report_section "Workstation readiness"
_smoke_run_summary "daily driver check" "Daily driver check complete" \
  bash "${ROOT}/system/daily_driver_check.sh"
_smoke_run "system.sh daily-driver" 0 bash "${ROOT}/system/system.sh" daily-driver
_smoke_run "run.sh --daily-driver-check" 0 bash "${ROOT}/run.sh" --daily-driver-check
_smoke_run_summary "run.sh --post-update-check" "Post-update summary" \
  bash "${ROOT}/run.sh" --post-update-check
_smoke_run "run.sh --disk-summary" 0 bash "${ROOT}/run.sh" --disk-summary
_smoke_run "fedora.sh --daily-driver-check (legacy redirect)" 0 bash "${ROOT}/fedora.sh" --daily-driver-check
_smoke_run_summary "luks-readiness" "LUKS summary" bash "${ROOT}/system/system.sh" luks-readiness
_smoke_run_summary "post-update-check" "Post-update summary" \
  bash "${ROOT}/system/system.sh" post-update-check
_smoke_run "luks-readiness --add-passphrase non-interactive" 1 \
  bash "${ROOT}/system/luks_readiness.sh" --add-passphrase </dev/null

theme_report_section "Health snapshot"
_smoke_run "health snapshot refresh" 0 bash "${ROOT}/system/health_snapshot.sh" --refresh --quiet
_smoke_run "health snapshot show" 0 bash "${ROOT}/system/health_snapshot.sh" --show
RUNS=$((RUNS + 1))
health_ec=0
health_out="$(bash "${ROOT}/system/health_snapshot.sh" --show 2>&1)" || health_ec=$?
if [[ "${health_ec}" -eq 0 ]] \
  && ! grep -qE 'tmpfs|devtmpfs|efivarfs' <<< "${health_out}" \
  && grep -q '\[Top memory\]' <<< "${health_out}"; then
  ok "health snapshot output filtered (no tmpfs/devtmpfs/efivarfs noise)"
else
  FAILS=$((FAILS + 1))
  FAIL_NAMES+=("health snapshot output filtered")
  warn "health snapshot output filtered — unexpected filesystem noise"
fi
RUNS=$((RUNS + 1))
startup_out="$(printf '0\n' | bash "${ROOT}/run.sh" 2>&1)" || startup_ec=$?
startup_ec="${startup_ec:-0}"
if [[ "${startup_ec}" -eq 0 ]] \
  && grep -q 'STATE / ' <<< "${startup_out}" \
  && ! grep -q '\[Memory\]' <<< "${startup_out}"; then
  ok "run.sh startup stays quiet (compact health line only)"
else
  FAILS=$((FAILS + 1))
  FAIL_NAMES+=("run.sh startup stays quiet")
  warn "run.sh startup health output too noisy or missing"
fi

theme_report_section "Interactive menus (non-interactive input)"
_smoke_menu "run.sh main menu" "${ROOT}/run.sh" '0\n'
_smoke_menu "run.sh system area back path" "${ROOT}/run.sh" '6\n0\n0\n'
_smoke_menu "run.sh install hub back path" "${ROOT}/run.sh" '5\n0\n0\n'
RUNS=$((RUNS + 1))
identity_menu_out="$(printf '5\n5\n0\n0\n0\n' | NO_COLOR=1 bash "${ROOT}/run.sh" 2>&1)" || identity_menu_ec=$?
identity_menu_ec="${identity_menu_ec:-0}"
if [[ "${identity_menu_ec}" -eq 0 ]] \
  && grep -q 'SET / Install workstation' <<< "${identity_menu_out}" \
  && grep -q 'ADR / Android RE tools' <<< "${identity_menu_out}" \
  && grep -q 'UPD / Update Fedora' <<< "${identity_menu_out}" \
  && ! grep -qE 'AND /|[⚙◈▣🖥⚡◇]' <<< "${identity_menu_out}"; then
  ok "runtime menus use the shared technical identity"
else
  FAILS=$((FAILS + 1))
  FAIL_NAMES+=("runtime menu visual identity")
  warn "runtime menus contain stale lane styling"
fi
_smoke_menu "Android core broad-install cancellation" "${ROOT}/run.sh" \
  '5\n5\n1\n1\nn\n\n0\n0\n0\n0\n'
_smoke_run "run.sh --profile research --plan" 0 bash "${ROOT}/run.sh" --profile research --plan
_smoke_menu "run.sh install all profiles submenu" "${ROOT}/run.sh" '5\n8\n0\n0\n0\n'
_smoke_menu "run.sh system disk/memory route" "${ROOT}/run.sh" '6\n8\n1\n0\n0\n0\n'
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
    "Next:    ./run.sh --inspect --format text"
  exit 0
fi

theme_summary_box "Smoke test summary" \
  "Result: FAILED" \
  "Runs: ${RUNS}" \
  "Failed: ${FAILS}" \
  "Next: review failed checks below"
theme_fail_list "${FAIL_NAMES[@]}"
exit 1
