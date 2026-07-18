#!/usr/bin/env bash
# lib/workflows.sh — chained workstation workflows (update · install · verify · onboard)
# Version: 0.2.0
#
# Source after lib/common.sh (and system/lib/menu.sh when using menu runners).
# Do not execute directly.

if [[ -n "${FEDORA_WORKFLOWS_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_WORKFLOWS_SH_LOADED=1

_WORKFLOWS_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_WORKFLOWS_LIB_DIR}/common.sh"
# shellcheck source=logging.sh
source "${_WORKFLOWS_LIB_DIR}/logging.sh"
# shellcheck source=theme.sh
source "${_WORKFLOWS_LIB_DIR}/theme.sh"

workflow_root() {
  printf '%s\n' "${FEDORA_ROOT:-$(fedora_toolkit_root)}"
}

# workflow_run_update QUICK ROOT
# Returns update script exit code.
workflow_run_update() {
  local quick="${1:-0}"
  local root="${2:-$(workflow_root)}"
  local -a args=()
  (( quick )) && args+=(--quick)
  info "Update logs to: $(log_dir)/system_update.log"
  if [[ "${FEDORA_UPDATE_TEST_MODE:-0}" == 1 ]]; then
    FEDORA_UPDATE_TEST_MODE=1 bash "${root}/system/system_update.sh" "${args[@]}"
    return $?
  fi
  sudo -E bash "${root}/system/system_update.sh" "${args[@]}"
}

# workflow_run_post_update ROOT
workflow_run_post_update() {
  local root="${1:-$(workflow_root)}"
  bash "${root}/system/post_update_check.sh"
}

# workflow_daily_sync QUICK ROOT [SKIP_POST]
# Full daily path: dnf upgrade → post-update validation.
workflow_daily_sync() {
  local quick="${1:-0}"
  local root="${2:-$(workflow_root)}"
  local skip_post="${3:-0}"
  local update_ec=0 post_ec=0

  theme_init
  theme_set_lane update
  theme_lane_banner "Daily Fedora sync" update
  theme_meta_line "HOST / $(hostname) · USER / $(real_user)"
  theme_meta_line "STEPS / update → post-update check"
  theme_rule '─'
  echo

  theme_report_progress 1 2 "Fedora system update"
  workflow_run_update "${quick}" "${root}" || update_ec=$?
  echo

  if (( skip_post )); then
    theme_summary_box "Daily sync" \
      "Update: $( (( update_ec == 0 )) && printf done || printf 'exit %s' "${update_ec}" )" \
      "Post-update: skipped" \
      "Next: ./run.sh --post-update-check"
    return "${update_ec}"
  fi

  theme_report_progress 2 2 "Post-update check"
  workflow_run_post_update "${root}" || post_ec=$?
  echo

  if (( update_ec == 0 && post_ec == 0 )); then
    theme_summary_box "Daily sync complete" \
      "Update: passed" \
      "Post-update: passed" \
      "Next: ./run.sh  or  ./run.sh --doctor"
    return 0
  fi

  theme_summary_box "Daily sync complete" \
    "Update: $( (( update_ec == 0 )) && printf passed || printf FAILED )" \
    "Post-update: $( (( post_ec == 0 )) && printf passed || printf review )" \
    "Next: review output above · logs: $(log_dir)/system_update.log"
  return $(( update_ec != 0 ? update_ec : post_ec ))
}

workflow_fresh_machine_hint() {
  theme_section "Fresh machine path"
  theme_note_kv "1" "./setup.sh  or  ./run.sh --onboard"
  theme_note_kv "2" "./run.sh --check"
  theme_note_kv "3" "./install.sh research --yes   (or ./run.sh --rebuild --yes)"
  theme_note_kv "4" "./run.sh --doctor"
  theme_note_kv "Daily" "./run.sh --daily   (update + post-update)"
  theme_note_kv "Profiles" "./install.sh list"
}

# workflow_onboard_fresh_machine ROOT [SKIP_SETUP]
# Guided first-run: setup → self-test → optional rebuild.
workflow_onboard_fresh_machine() {
  local root="${1:-$(workflow_root)}"
  local skip_setup="${2:-0}"
  local setup_ec=0 check_ec=0 rebuild_ec=0

  theme_init
  theme_set_lane rebuild
  theme_lane_banner "Fresh machine onboarding" rebuild
  theme_meta_line "HOST / $(hostname) · USER / $(real_user)"
  theme_meta_line "ROOT / ${root}"
  theme_rule '─'
  echo

  workflow_fresh_machine_hint
  echo

  if (( ! skip_setup )); then
    theme_report_progress 1 3 "Repository setup validation"
    bash "${root}/setup.sh" || setup_ec=$?
    echo
    if (( setup_ec != 0 )); then
      theme_summary_box "Onboarding paused" \
        "Setup: failed" \
        "Next: fix validation above · ./setup.sh"
      return "${setup_ec}"
    fi
  fi

  theme_report_progress 2 3 "Repository self-test"
  # shellcheck source=check.sh
  source "${root}/lib/check.sh"
  fedora_toolkit_check "${root}" 0 0 || check_ec=$?
  echo

  if (( check_ec != 0 )); then
    warn "Self-test reported issues — review before rebuild"
    if ! confirm "Continue to guided rebuild anyway?"; then
      theme_summary_box "Onboarding paused" \
        "Self-test: review needed" \
        "Next: ./run.sh --check --fix-repos"
      return "${check_ec}"
    fi
  fi

  theme_report_progress 3 3 "Guided rebuild (research profile)"
  local rebuild_state="skipped"
  if (( skip_setup )) || confirm "Run guided rebuild now? (--yes, research profile)"; then
    rebuild_state="done"
    bash "${root}/run.sh" --rebuild --yes --profile research || {
      rebuild_ec=$?
      rebuild_state="failed"
    }
  else
    theme_note "Skipped rebuild — run: ./install.sh research --yes"
  fi
  echo

  if [[ "${rebuild_state}" == "failed" ]]; then
    theme_summary_box "Onboarding finished" \
      "Rebuild: review failures above" \
      "Next: ./run.sh --doctor · logs: $(log_dir)/fedora_rebuild.log"
    return $(( check_ec != 0 ? check_ec : rebuild_ec ))
  fi

  theme_summary_box "Onboarding complete" \
    "Setup: OK" \
    "Rebuild: ${rebuild_state}" \
    "Next: source ~/.bashrc · ./run.sh --doctor · ./run.sh --daily"
  return "${check_ec}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
