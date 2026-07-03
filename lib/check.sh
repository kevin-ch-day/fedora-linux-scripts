#!/usr/bin/env bash
# lib/check.sh — unified toolkit readiness checks
# Version: 0.3.0
#
# Source after lib/common.sh.
# Used by: ./run.sh --check

if [[ -n "${FEDORA_CHECK_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_CHECK_SH_LOADED=1

_CHECK_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_CHECK_LIB_DIR}/common.sh"
# shellcheck source=theme.sh
source "${_CHECK_LIB_DIR}/theme.sh"
# shellcheck source=baseline.sh
source "${_CHECK_LIB_DIR}/baseline.sh"
# shellcheck source=host_context.sh
source "${_CHECK_LIB_DIR}/host_context.sh"

# fedora_toolkit_check ROOT [full_smoke] [fix_repos]
# full_smoke=1 → smoke_test.sh without --quick
# fix_repos=1  → run sudo fix_dnf_repo_permissions before rebuild step
fedora_toolkit_check() {
  local root="${1:?toolkit root required}"
  local full_smoke="${2:-0}"
  local fix_repos="${3:-0}"
  local val_ec=0 smoke_ec=0 ready_ec=0 doctor_ec=0
  local smoke_args=(--quick)
  local next_hint="Fix issues above, then: ./run.sh --check"
  local steps=3 step=0

  (( full_smoke )) && smoke_args=()
  if (( full_smoke )); then
    steps=4
  fi

  theme_init
  theme_set_lane audit
  theme_lane_banner "Fedora toolkit check" audit
  theme_meta_line "Host: $(hostname) · User: $(real_user)"
  theme_meta_line "Context: $(host_context_posture_summary | tr -d '\n')"
  theme_meta_line "Root: ${root}"
  if (( full_smoke )); then
    theme_meta_line "Mode: full (includes doctor smoke tests)"
  fi
  if (( fix_repos )); then
    theme_meta_line "Fix repos: yes (sudo before rebuild check)"
  fi
  theme_rule '─'
  echo

  local unreadable_repos=""
  unreadable_repos="$(baseline_unreadable_repo_files 2>/dev/null || true)"
  if [[ -n "${unreadable_repos}" ]]; then
    if (( fix_repos )); then
      info "Unreadable DNF repo files detected — will fix before rebuild check"
      printf '%s\n' "${unreadable_repos}" | sed 's/^/  /'
      echo
    else
      warn "DNF repo files not readable as $(real_user) — rebuild check may fail"
      printf '%s\n' "${unreadable_repos}" | sed 's/^/  /'
      info "Fix: ./run.sh --check --fix-repos   or   sudo ./run.sh --fix-repos"
      echo
    fi
  fi

  step=$((step + 1))
  theme_report_progress "${step}" "${steps}" "Repo validation"
  bash "${root}/validate.sh" --quick --install-audit || val_ec=$?
  echo

  step=$((step + 1))
  theme_report_progress "${step}" "${steps}" "Smoke tests"
  FEDORA_SKIP_CHECK_SMOKE=1 bash "${root}/smoke_test.sh" "${smoke_args[@]}" || smoke_ec=$?
  echo

  if (( full_smoke )); then
    step=$((step + 1))
    theme_report_progress "${step}" "${steps}" "Fedora doctor"
    bash "${root}/system/research_doctor.sh" --android-only || doctor_ec=$?
    echo
  fi

  if (( fix_repos )) && baseline_unreadable_repo_files 2>/dev/null | grep -q .; then
    info "Fixing DNF repo permissions (sudo)..."
    if sudo bash "${root}/system/fix_dnf_repo_permissions.sh"; then
      ok "Repo permissions fixed"
    else
      warn "Repo permission fix failed or was cancelled"
    fi
    echo
  fi

  step=$((step + 1))
  theme_report_progress "${step}" "${steps}" "Rebuild readiness"
  bash "${root}/system/rebuild_readiness_check.sh" || ready_ec=$?
  echo

  if (( ready_ec != 0 )) && baseline_unreadable_repo_files 2>/dev/null | grep -q .; then
    next_hint="sudo ./run.sh --fix-repos  →  ./run.sh --check"
  elif (( ready_ec != 0 )); then
    next_hint="Resolve rebuild readiness issues  →  ./run.sh --check"
  elif (( val_ec != 0 || smoke_ec != 0 || doctor_ec != 0 )); then
    next_hint="Fix repo/smoke/doctor failures  →  ./run.sh --check"
  fi

  if (( val_ec == 0 && smoke_ec == 0 && ready_ec == 0 && doctor_ec == 0 )); then
    if (( full_smoke )); then
      theme_summary_box "Check complete" \
        "Result:     READY" \
        "Validate:   passed" \
        "Smoke:      passed" \
        "Doctor:     passed" \
        "Rebuild:    ready" \
        "Next:       ./run.sh --daily  ·  ./run.sh --rebuild"
    else
      theme_summary_box "Check complete" \
        "Result:     READY" \
        "Validate:   passed" \
        "Smoke:      passed" \
        "Rebuild:    ready" \
        "Next:       ./run.sh --daily  ·  ./install.sh workstation --plan"
    fi
    return 0
  fi

  if (( full_smoke )); then
    theme_summary_box "Check complete" \
      "Result:     NOT READY" \
      "Validate:   $( (( val_ec == 0 )) && printf passed || printf FAILED )" \
      "Smoke:      $( (( smoke_ec == 0 )) && printf passed || printf FAILED )" \
      "Doctor:     $( (( doctor_ec == 0 )) && printf passed || printf FAILED )" \
      "Rebuild:    $( (( ready_ec == 0 )) && printf ready || printf 'NOT READY' )" \
      "Next:       ${next_hint}"
  else
    theme_summary_box "Check complete" \
      "Result:     NOT READY" \
      "Validate:   $( (( val_ec == 0 )) && printf passed || printf FAILED )" \
      "Smoke:      $( (( smoke_ec == 0 )) && printf passed || printf FAILED )" \
      "Rebuild:    $( (( ready_ec == 0 )) && printf ready || printf 'NOT READY' )" \
      "Next:       ${next_hint}"
  fi
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
