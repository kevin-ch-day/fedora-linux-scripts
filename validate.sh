#!/usr/bin/env bash
# validate.sh — Repo health checks (syntax, entry points, optional ShellCheck)
# Version: 0.1.7
#
# Run from repo root:
#   ./validate.sh
#   ./validate.sh --quick        # syntax + entry points only
#   ./validate.sh --shellcheck   # include ShellCheck (-S warning)

set -uo pipefail

VALIDATE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${VALIDATE_ROOT}/lib/common.sh"

QUICK=0
DO_SHELLCHECK=0
DO_SMOKE=0
DO_INSTALL_AUDIT=0
FAILURES=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Repository validation for Fedora Workstation Control.

Options:
  --quick          Skip ShellCheck (default when shellcheck missing)
  --shellcheck     Run ShellCheck at -S warning on active scripts
  --smoke          Run ./smoke_test.sh --quick after static checks
  --install-audit  Run ./install_audit.sh --quick after static checks
  --help, -h       Show this help

  Checks:
  - bash -n on active scripts (excludes legacy/)
  - entry points (lib/entry_points.sh)
  - CI workflow and MobSF compose secrets pattern
  - docs/GETTING-STARTED.md and docs/README.md present
  - optional: shellcheck -S warning
  - optional: ./smoke_test.sh --quick
  - optional: ./install_audit.sh --quick
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --quick) QUICK=1; shift ;;
    --shellcheck) DO_SHELLCHECK=1; shift ;;
    --smoke) DO_SMOKE=1; shift ;;
    --install-audit) DO_INSTALL_AUDIT=1; shift ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

if (( DO_SHELLCHECK == 0 && QUICK == 0 )) && have shellcheck; then
  DO_SHELLCHECK=1
fi

_validate_fail() {
  warn "$*"
  FAILURES=$(( FAILURES + 1 ))
}

_validate_ok() {
  ok "$*"
}

# shellcheck source=lib/theme.sh
source "${VALIDATE_ROOT}/lib/theme.sh"
theme_init
theme_set_lane audit

theme_lane_banner "Fedora Workstation Control validation" audit
theme_meta_line "ROOT / ${VALIDATE_ROOT}"
theme_rule '─'
echo

theme_report_section "Syntax (bash -n, excluding legacy/)"
syntax_fail=0
while IFS= read -r -d '' script; do
  if ! bash -n "${script}" 2>/dev/null; then
    syntax_fail=1
    _validate_fail "bash -n failed: ${script#"${VALIDATE_ROOT}/"}"
  fi
done < <(find "${VALIDATE_ROOT}" -name '*.sh' -type f ! -path "${VALIDATE_ROOT}/legacy/*" -print0)
(( syntax_fail == 0 )) && _validate_ok "bash -n passed for active scripts"

theme_report_section "Entry points"
_ep_failures=0
# shellcheck source=lib/entry_points.sh
source "${VALIDATE_ROOT}/lib/entry_points.sh"
if ! fedora_entry_points_check "${VALIDATE_ROOT}" _ep_failures; then
  FAILURES=$((FAILURES + _ep_failures))
fi

theme_report_section "CI workflow"
if [[ -f "${VALIDATE_ROOT}/.github/workflows/validate.yml" ]]; then
  _validate_ok ".github/workflows/validate.yml present"
else
  _validate_fail "missing: .github/workflows/validate.yml"
fi

theme_report_section "MobSF compose secrets"
compose_file="${VALIDATE_ROOT}/mobsf/compose/docker-compose.yml"
if [[ -f "${compose_file}" ]] && grep -q '\${POSTGRES_PASSWORD}' "${compose_file}"; then
  _validate_ok "compose uses \${POSTGRES_PASSWORD}"
elif [[ -f "${compose_file}" ]] && grep -q 'POSTGRES_PASSWORD=password' "${compose_file}"; then
  _validate_fail "compose has hardcoded POSTGRES_PASSWORD"
else
  _validate_fail "compose POSTGRES_PASSWORD pattern not recognized"
fi

theme_report_section "Documentation"
for doc in docs/README.md docs/GETTING-STARTED.md docs/INSTALL-PROFILES.md docs/AUDIT.md \
  docs/architecture/ADR-0001-project-identity-and-control-model.md \
  docs/architecture/INVENTORY-V1.md docs/design/VISUAL-IDENTITY.md \
  schemas/inventory-v1.schema.json mobsf/GUIDE.md; do
  if [[ -f "${VALIDATE_ROOT}/${doc}" ]]; then
    _validate_ok "${doc}"
  else
    _validate_fail "missing: ${doc}"
  fi
done

theme_report_section "Visual identity"
theme_contract_ok=1
shared_accent="$(theme_lane_accent_code main)"
for lane in main system dev android mobsf rebuild audit; do
  marker="$(theme_lane_icon "${lane}")"
  if [[ "$(theme_lane_accent_code "${lane}")" != "${shared_accent}" ]]; then
    _validate_fail "lane ${lane} does not use the shared signal accent"
    theme_contract_ok=0
  fi
  if [[ ! "${marker}" =~ ^[A-Z0-9]{3}\ /\ $ ]]; then
    _validate_fail "lane ${lane} marker is not a three-character ASCII technical marker"
    theme_contract_ok=0
  fi
done
if [[ "${shared_accent}" == "$(theme_status_code success)" ]] \
  || [[ "${shared_accent}" == "$(theme_status_code warning)" ]] \
  || [[ "${shared_accent}" == "$(theme_status_code failure)" ]]; then
  _validate_fail "signal accent reuses a semantic status token"
  theme_contract_ok=0
fi
for token in THEME_SIGNAL THEME_STATUS_SUCCESS THEME_STATUS_WARNING \
  THEME_STATUS_FAILURE THEME_STATUS_MUTED; do
  if ! declare -p "${token}" >/dev/null 2>&1; then
    _validate_fail "undefined semantic theme token: ${token}"
    theme_contract_ok=0
  fi
done
for disable_var in NO_COLOR FEDORA_NO_COLOR; do
  if ! (
    unset NO_COLOR FEDORA_NO_COLOR
    printf -v "${disable_var}" '%s' 1
    theme_init
    [[ "${THEME_USE_COLOR}" -eq 0 ]]
    [[ -z "${THEME_SIGNAL}${THEME_STATUS_SUCCESS}${THEME_STATUS_WARNING}${THEME_STATUS_FAILURE}" ]]
  ); then
    _validate_fail "${disable_var} does not fully disable semantic color tokens"
    theme_contract_ok=0
  fi
done
for cols in 120 100 80 60; do
  resolved="$(COLUMNS="${cols}" theme_resolved_width)"
  if (( resolved > cols - 4 || resolved < 24 )); then
    _validate_fail "theme width ${resolved} is invalid at ${cols} columns"
    theme_contract_ok=0
  fi
done
preview_plain="$(COLUMNS=60 NO_COLOR=1 bash "${VALIDATE_ROOT}/theme_preview.sh")"
preview_max_width="$(
  while IFS= read -r line; do
    printf '%s\n' "${#line}"
  done <<< "${preview_plain}" | sort -nr | head -1
)"
if (( preview_max_width > 56 )); then
  _validate_fail "plain theme preview exceeds safe width at 60 columns (${preview_max_width})"
  theme_contract_ok=0
fi
for required_label in \
  "CTL / Fedora Workstation Control" \
  "STATE / WARN" \
  "HOST /" \
  "ACTION / Inspect host" \
  "ADR / Android research" \
  "DANGER / Reset configuration" \
  "[ABSENT] adb is not installed" \
  "[UNAVAIL] GPU sensor did not report" \
  "[SKIP] Database check intentionally deferred" \
  "Progress  2/8" \
  "25%"; do
  if ! grep -Fq "${required_label}" <<< "${preview_plain}"; then
    _validate_fail "plain theme preview missing hierarchy label: ${required_label}"
    theme_contract_ok=0
  fi
done
if [[ "${preview_plain}" == *$'\r'* ]]; then
  _validate_fail "plain theme preview contains carriage-return cursor movement"
  theme_contract_ok=0
fi
(( theme_contract_ok == 1 )) \
  && _validate_ok "accent, states, danger, progress, plain hierarchy, and widths"

theme_report_section "Output identity audit"
identity_files=(
  run.sh
  lib/menu.sh
  lib/theme.sh
  lib/health_snapshot.sh
  dev/lib/menu.sh
  android/lib/menu.sh
  system/lib/menu.sh
  system/system_update.sh
  system/system_monitor.sh
  system/health_snapshot.sh
)
identity_stale="$(
  grep -nE 'AND /|⚙|◈|▣|🖥|⚡|◇' \
    "${identity_files[@]/#/${VALIDATE_ROOT}/}" 2>/dev/null || true
)"
if [[ -n "${identity_stale}" ]]; then
  printf '%s\n' "${identity_stale}" | head -20
  _validate_fail "active control surfaces contain legacy visual markers"
else
  _validate_ok "active control surfaces use technical markers"
fi

theme_report_section "Host inspector"
if python3 -c 'import pathlib, sys; p=pathlib.Path(sys.argv[1]); compile(p.read_text(), str(p), "exec")' \
  "${VALIDATE_ROOT}/libexec/inspect_host.py" 2>/dev/null; then
  _validate_ok "libexec/inspect_host.py syntax"
else
  _validate_fail "libexec/inspect_host.py syntax failed"
fi
if python3 -c 'import json, pathlib, sys; json.loads(pathlib.Path(sys.argv[1]).read_text())' \
  "${VALIDATE_ROOT}/schemas/inventory-v1.schema.json" 2>/dev/null; then
  _validate_ok "inventory-v1.schema.json valid JSON"
else
  _validate_fail "inventory-v1.schema.json is not valid JSON"
fi

theme_report_section "Install profiles"
# shellcheck source=lib/profiles.sh
source "${VALIDATE_ROOT}/lib/profiles.sh"
profile_fail=0
for p in $(profile_list_names); do
  if profile_validate_steps "${VALIDATE_ROOT}" "${p}"; then
    _validate_ok "profile ${p} — step scripts present"
  else
    profile_fail=1
    _validate_fail "profile ${p} — missing step script(s)"
  fi
done
(( profile_fail == 0 )) || true

if (( DO_SHELLCHECK )); then
  theme_report_section "ShellCheck (-S warning, excluding legacy/)"
  if sc_out="$(find "${VALIDATE_ROOT}" -name '*.sh' -type f ! -path "${VALIDATE_ROOT}/legacy/*" -print0 \
    | xargs -0 shellcheck -S warning 2>&1)"; then
    _validate_ok "ShellCheck clean"
  else
    printf '%s\n' "${sc_out}" | head -40
    _validate_fail "ShellCheck reported warnings (see above)"
  fi
elif (( QUICK == 0 )); then
  echo
  warn "ShellCheck not installed — skip with --quick or install shellcheck"
fi

if (( DO_SMOKE )); then
  theme_report_section "Smoke tests (./smoke_test.sh --quick)"
  if bash "${VALIDATE_ROOT}/smoke_test.sh" --quick; then
    _validate_ok "smoke_test.sh --quick passed"
  else
    _validate_fail "smoke_test.sh --quick failed"
  fi
fi

if (( DO_INSTALL_AUDIT )); then
  theme_report_section "Install audit (./install_audit.sh --quick)"
  if bash "${VALIDATE_ROOT}/install_audit.sh" --quick; then
    _validate_ok "install_audit.sh --quick passed"
  else
    _validate_fail "install_audit.sh --quick failed"
  fi
fi

echo
if (( FAILURES == 0 )); then
  theme_summary_box "Validation summary" \
    "Result: passed" \
    "Issues: 0" \
    "Next: ./run.sh --inspect --format text"
  exit 0
fi
theme_summary_box "Validation summary" \
  "Result: FAILED" \
  "Issues: ${FAILURES}" \
  "Next: fix issues above and re-run ./validate.sh"
err "Validation failed (${FAILURES} issue(s))"
exit 1
