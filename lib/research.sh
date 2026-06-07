#!/usr/bin/env bash
# lib/research.sh — full research workstation doctor orchestration
# Version: 0.1.6
#
# Source from system/research_doctor.sh or launchers.
# Do not execute directly.

if [[ -n "${FEDORA_RESEARCH_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_RESEARCH_SH_LOADED=1

_RESEARCH_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_RESEARCH_LIB_DIR}/common.sh"
# shellcheck source=theme.sh
source "${_RESEARCH_LIB_DIR}/theme.sh"

research_doctor_usage() {
  cat <<EOF
Usage: research_doctor.sh [--android-only] [--mobsf-only]

Runs readiness checks for the Fedora research workstation.

  ./fedora.sh --doctor              Fedora doctor (repo · lanes · workstation health)
  research_doctor.sh --android-only Same as ./fedora.sh --doctor
  research_doctor.sh                Full check incl. MobSF (rebuild finale)
  ./mobsf.sh --doctor               MobSF stack health (separate entry)

Exit code: 0 if all enabled checks pass, 1 otherwise.
EOF
}

# research_check_entry_points FEDORA_ROOT — verify main launchers and fedora.sh layout
research_check_entry_points() {
  local fedora_root="${1:?fedora root required}"
  local rc=0

  # shellcheck source=entry_points.sh
  source "${_RESEARCH_LIB_DIR}/entry_points.sh"
  export FEDORA_ENTRY_POINTS_BANNER=1
  fedora_entry_points_check "${fedora_root}" || rc=1
  echo
  return "${rc}"
}

# research_doctor_run FEDORA_ROOT DO_ANDROID DO_MOBSF
research_doctor_run() {
  local fedora_root="${1:?fedora root required}"
  local do_android="${2:-1}"
  local do_mobsf="${3:-1}"
  local rc=0

  try_run research_check_entry_points "${fedora_root}" || rc=1
  echo

  if (( do_android )); then
    try_run bash "${fedora_root}/android/doctor_android_research.sh" || rc=1
    echo
  fi

  if (( do_mobsf )); then
    try_run bash "${fedora_root}/mobsf/mobsf_doctor.sh" || rc=1
  fi

  if (( do_android && ! do_mobsf )); then
    echo
    theme_rule '─'
    if (( rc == 0 )); then
      ok "Fedora doctor: READY (repo · lanes · workstation health)"
    else
      warn "Fedora doctor: ISSUES (see sections above)"
    fi
    info "MobSF stack is separate: ./mobsf.sh --doctor"
    theme_rule '─'
  fi

  if (( do_android && do_mobsf )); then
    echo
    theme_rule '─'
    if (( rc == 0 )); then
      ok "Combined result: READY (Android + MobSF)"
    else
      warn "Combined result: ISSUES (see sections above)"
      info "Android: ./android/doctor_android_research.sh"
      info "MobSF:   ./mobsf.sh --doctor  (install: ./mobsf.sh install)"
    fi
    theme_rule '─'
  fi

  return "${rc}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
