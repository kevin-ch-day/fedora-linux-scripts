#!/usr/bin/env bash
# validate.sh — Repo health checks (syntax, entry points, optional ShellCheck)
# Version: 0.1.5
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

Quick repo validation for fedora-linux-scripts.

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

theme_lane_banner "Fedora toolkit validation" audit
theme_meta_line "Root: ${VALIDATE_ROOT}"
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
for doc in docs/README.md docs/GETTING-STARTED.md docs/AUDIT.md mobsf/GUIDE.md; do
  if [[ -f "${VALIDATE_ROOT}/${doc}" ]]; then
    _validate_ok "${doc}"
  else
    _validate_fail "missing: ${doc}"
  fi
done

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
    "Next: ./fedora.sh --check"
  exit 0
fi
theme_summary_box "Validation summary" \
  "Result: FAILED" \
  "Issues: ${FAILURES}" \
  "Next: fix issues above and re-run ./validate.sh"
err "Validation failed (${FAILURES} issue(s))"
exit 1
