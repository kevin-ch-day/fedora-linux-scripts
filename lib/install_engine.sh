#!/usr/bin/env bash
# lib/install_engine.sh — run named install/rebuild profiles (step engine)
# Version: 0.3.0
#
# Source after lib/common.sh, lib/theme.sh, lib/profiles.sh, lib/logging.sh.
# Do not execute directly.

if [[ -n "${FEDORA_INSTALL_ENGINE_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_INSTALL_ENGINE_SH_LOADED=1

_INSTALL_ENGINE_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_INSTALL_ENGINE_LIB_DIR}/common.sh"
# shellcheck source=theme.sh
source "${_INSTALL_ENGINE_LIB_DIR}/theme.sh"
# shellcheck source=logging.sh
source "${_INSTALL_ENGINE_LIB_DIR}/logging.sh"
# shellcheck source=profiles.sh
source "${_INSTALL_ENGINE_LIB_DIR}/profiles.sh"

# install_engine_run_step ROOT TITLE REL SUDO_MODE EXTRA...
install_engine_run_step() {
  local root="$1"
  local title="$2"
  local rel="$3"
  local sudo_mode="${4:-none}"
  shift 4
  local extra=("$@")
  local script="${root}/${rel}"
  local rc=0

  INSTALL_ENGINE_STEP=$(( INSTALL_ENGINE_STEP + 1 ))

  echo
  theme_report_step "${INSTALL_ENGINE_STEP}" "${INSTALL_ENGINE_TOTAL}" "${title}" "Script: ${rel}"

  if (( INSTALL_ENGINE_USE_LOG )); then
    log_step "${INSTALL_ENGINE_STEP}" "${INSTALL_ENGINE_TOTAL}" "STEP: ${title} (${rel})"
  fi

  if (( INSTALL_ENGINE_DRY_RUN )); then
    info "(dry-run) would execute: ${rel} ${extra[*]:-}"
    (( INSTALL_ENGINE_USE_LOG )) && log_info "(dry-run) would execute: ${rel} ${extra[*]:-}"
    return 0
  fi

  if (( INSTALL_ENGINE_AUTO_YES )) || confirm "Run this step?"; then
    assert_file "${script}" "Install step script missing: ${rel}"
    case "${sudo_mode}" in
      sudo-E) sudo -E bash "${script}" "${extra[@]}" || rc=$? ;;
      sudo) sudo bash "${script}" "${extra[@]}" || rc=$? ;;
      none|*) bash "${script}" "${extra[@]}" || rc=$? ;;
    esac
    if (( rc != 0 )); then
      warn "Step failed (exit ${rc}): ${title}"
      INSTALL_ENGINE_FAILED=$(( INSTALL_ENGINE_FAILED + 1 ))
      (( INSTALL_ENGINE_USE_LOG )) && log_warn "Step failed: ${title} (exit ${rc})"
    else
      ok "Step complete: ${title}"
      (( INSTALL_ENGINE_USE_LOG )) && log_info "Step complete: ${title}"
    fi
  else
    warn "Skipped: ${title}"
    (( INSTALL_ENGINE_USE_LOG )) && log_warn "Skipped: ${title}"
  fi
}

install_engine_maybe_mobsf() {
  local root="$1"
  local profile="$2"
  (( ${FEDORA_SKIP_MOBSF:-0} )) && return 0
  profile_wants_mobsf "${profile}" || return 0

  # shellcheck source=mobsf.sh
  source "${root}/lib/mobsf.sh"

  if (( INSTALL_ENGINE_DRY_RUN || INSTALL_ENGINE_PLAN_ONLY )); then
    info "(dry-run) would offer: MobSF install/reset"
    return 0
  fi

  if (( INSTALL_ENGINE_AUTO_YES )); then
    if mobsf_compose_installed; then
      info "MobSF compose present — skipping auto install"
      return 0
    fi
    install_engine_run_step "${root}" "MobSF install" "mobsf/mobsf_install.sh" "sudo-E"
    return 0
  fi

  if confirm "Run MobSF install/reset? (install if first time; reset if stack exists)"; then
    if mobsf_compose_installed; then
      install_engine_run_step "${root}" "MobSF reset (keep data)" "mobsf/mobsf_reset.sh" "sudo-E" --keep
    else
      install_engine_run_step "${root}" "MobSF install" "mobsf/mobsf_install.sh" "sudo-E"
    fi
  fi
}

install_engine_maybe_doctor() {
  local root="$1"
  local profile="$2"
  local doc=""
  (( ${FEDORA_SKIP_DOCTOR:-0} )) && return 0
  profile_wants_doctor "${profile}" || return 0
  doc="$(profile_doctor_script "${profile}")" || return 0

  if (( INSTALL_ENGINE_DRY_RUN || INSTALL_ENGINE_PLAN_ONLY )); then
    info "(plan) optional doctor: ${doc}"
    return 0
  fi

  if (( INSTALL_ENGINE_AUTO_YES )) || confirm "Run doctor after install steps? (${doc})"; then
    install_engine_run_step "${root}" "Doctor" "${doc}" "none"
  fi
}

# install_engine_plan_profile ROOT PROFILE
# Print numbered step plan (no execution).
install_engine_plan_profile() {
  local root="${1:?root required}"
  local profile="${2:?profile required}"
  local n=0 title rel sudo_mode args_line extra
  local core_steps optional=0

  profile_is_valid "${profile}" || die "Unknown profile: ${profile} (try: ./install.sh list)"

  theme_init
  theme_set_lane rebuild
  theme_lane_banner "Install plan: ${profile}" rebuild
  theme_meta_line "$(profile_description "${profile}")"
  theme_meta_line "RISK / $(profile_risk_level "${profile}") · IMPACT / $(profile_impact_summary "${profile}")"
  theme_meta_line "Root: ${root}"
  theme_rule '─'
  echo

  core_steps="$(profile_step_count "${profile}")"
  info "Core steps: ${core_steps}"

  while IFS=$'\t' read -r title rel sudo_mode args_line; do
    [[ -n "${title}" ]] || continue
    n=$((n + 1))
    extra=""
    [[ -n "${args_line}" ]] && extra=" ${args_line}"
    case "${sudo_mode}" in
      sudo-E) theme_note_kv "${n}" "${title} — sudo -E ${rel}${extra}" ;;
      sudo) theme_note_kv "${n}" "${title} — sudo ${rel}${extra}" ;;
      *) theme_note_kv "${n}" "${title} — ${rel}${extra}" ;;
    esac
    if [[ ! -f "${root}/${rel}" ]]; then
      warn "  missing script: ${rel}"
    fi
  done < <(profile_iter_steps "${profile}")

  if profile_wants_mobsf "${profile}"; then
    optional=$((optional + 1))
    theme_note_kv "$((n + optional))" "(optional) MobSF install/reset — mobsf/mobsf_install.sh"
  fi
  if profile_wants_doctor "${profile}"; then
    optional=$((optional + 1))
    local doc=""
    doc="$(profile_doctor_script "${profile}")" || doc="(unknown)"
    theme_note_kv "$((n + optional))" "(optional) Doctor — ${doc}"
  fi

  echo
  theme_note "Run: ./install.sh ${profile} [--yes] [--dry-run]"
  if profile_requires_service_ack "${profile}"; then
    theme_note "Auto mode: add --allow-service-start with --yes to acknowledge service activation"
  fi
  return 0
}

# install_engine_validate_profile ROOT PROFILE
# Returns 0 when all referenced scripts exist.
install_engine_validate_profile() {
  local root="${1:?root required}"
  local profile="${2:?profile required}"
  profile_validate_steps "${root}" "${profile}"
}

# install_engine_run_profile ROOT PROFILE AUTO_YES DRY_RUN USE_LOG [FROM_MENU] [PLAN_ONLY]
install_engine_run_profile() {
  local root="${1:?root required}"
  local profile="${2:?profile required}"
  local auto_yes="${3:-0}"
  local dry_run="${4:-0}"
  local use_log="${5:-0}"
  local from_menu="${6:-0}"
  local plan_only="${7:-0}"

  local row title rel sudo_mode extra args_line
  local core_steps=0

  profile_is_valid "${profile}" || die "Unknown profile: ${profile} (try: ./install.sh list)"

  if (( plan_only )); then
    install_engine_plan_profile "${root}" "${profile}"
    return 0
  fi

  if ! install_engine_validate_profile "${root}" "${profile}"; then
    die "Profile '${profile}' references missing scripts (fix repo or run: ./install.sh ${profile} --plan)"
  fi
  if (( auto_yes && ! dry_run )) \
    && profile_requires_service_ack "${profile}" \
    && [[ "${INSTALL_ENGINE_ALLOW_SERVICE_START:-0}" != 1 ]]; then
    die "Profile '${profile}' enables system services. Review --plan, then add --allow-service-start with --yes."
  fi

  INSTALL_ENGINE_AUTO_YES="${auto_yes}"
  INSTALL_ENGINE_DRY_RUN="${dry_run}"
  INSTALL_ENGINE_USE_LOG="${use_log}"
  INSTALL_ENGINE_PLAN_ONLY=0
  INSTALL_ENGINE_STEP=0
  INSTALL_ENGINE_FAILED=0

  core_steps="$(profile_step_count "${profile}")"
  INSTALL_ENGINE_TOTAL="${core_steps}"
  if profile_wants_mobsf "${profile}"; then
    INSTALL_ENGINE_TOTAL=$(( INSTALL_ENGINE_TOTAL + 1 ))
  fi
  if profile_wants_doctor "${profile}"; then
    INSTALL_ENGINE_TOTAL=$(( INSTALL_ENGINE_TOTAL + 1 ))
  fi

  theme_init
  theme_set_lane rebuild
  theme_lane_banner "Install profile: ${profile}" rebuild
  theme_meta_line "$(profile_description "${profile}")"
  theme_meta_line "RISK / $(profile_risk_level "${profile}")"
  theme_meta_line "IMPACT / $(profile_impact_summary "${profile}")"
  theme_meta_line "Root: ${root}"
  (( dry_run )) && theme_meta_line "Mode: dry-run"
  (( auto_yes )) && theme_meta_line "Mode: auto-yes"
  theme_rule '─'
  echo

  if (( use_log )); then
    init_script_logging "${FEDORA_LOG_REBUILD}" "install_profile_${profile}" "Profile: ${profile}"
    (( dry_run )) && log_warn "DRY RUN — no scripts will execute"
  fi

  info "Profile: ${profile} (${core_steps} core steps)"
  (( dry_run )) && warn "DRY RUN — no scripts will execute"
  (( use_log )) && info "Logging to: $(log_file_path "${FEDORA_LOG_REBUILD}")"

  while IFS=$'\t' read -r title rel sudo_mode args_line; do
    [[ -n "${title}" ]] || continue
    extra=()
    if [[ -n "${args_line}" ]]; then
      # shellcheck disable=SC2206
      extra=(${args_line})
    fi
    install_engine_run_step "${root}" "${title}" "${rel}" "${sudo_mode}" "${extra[@]}"
  done < <(profile_iter_steps "${profile}")

  install_engine_maybe_mobsf "${root}" "${profile}"
  install_engine_maybe_doctor "${root}" "${profile}"

  echo
  if (( dry_run )); then
    ok "Dry run for profile '${profile}' finished; no steps executed"
    theme_summary_box "Dry run complete" \
      "Profile: ${profile}" \
      "Changes: none" \
      "Next: review the plan; remove --dry-run only when ready"
    return 0
  fi

  if (( INSTALL_ENGINE_FAILED > 0 )); then
    warn "Profile '${profile}' finished with ${INSTALL_ENGINE_FAILED} failed step(s)"
  else
    ok "Profile '${profile}' finished"
  fi

  theme_summary_box "Profile complete" \
    "Profile: ${profile}" \
    "Failed: ${INSTALL_ENGINE_FAILED}" \
    "Next: $(profile_next_action "${profile}")"

  return $(( INSTALL_ENGINE_FAILED > 0 ? 1 : 0 ))
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
