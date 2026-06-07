#!/usr/bin/env bash
# fedora_rebuild.sh — Guided workstation rebuild sequence (implementation)
# Version: 0.4.6
#
# Prefer: ./fedora.sh --rebuild
#
# This script is retained for compatibility. When invoked directly it delegates
# to ./fedora.sh --rebuild (see FEDORA_REBUILD_VIA_FEDORA guard below).
#
# Run:
#   ./fedora.sh --rebuild              # preferred
#   ./fedora_rebuild.sh                # compatibility → fedora.sh --rebuild
#   ./fedora.sh --rebuild --yes        # no prompts between steps
#   ./fedora.sh --rebuild --dry-run    # show steps only
#   ./fedora.sh --rebuild --log        # tee output to logs/fedora_rebuild.log

set -euo pipefail

FEDORA_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Compatibility wrapper: direct callers go through fedora.sh (avoid loop below).
if [[ "${FEDORA_REBUILD_VIA_FEDORA:-}" != 1 ]]; then
  exec bash "${FEDORA_ROOT}/fedora.sh" --rebuild "$@"
fi
# shellcheck source=lib/common.sh
source "${FEDORA_ROOT}/lib/common.sh"
# shellcheck source=lib/logging.sh
source "${FEDORA_ROOT}/lib/logging.sh"

errors_init_script "fedora_rebuild.sh"

AUTO_YES=0
DRY_RUN=0
USE_LOG=0
SKIP_MOBSF=0
SKIP_DOCTOR=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Guided rebuild: system update → KVM/containers → Android core → RE tools →
verify → optional MobSF → research doctor.

Not included (run from Dev lane after rebuild): git, VS Code, Cinnamon desktop,
LAMP/phpMyAdmin — see docs/GETTING-STARTED.md § After rebuild.

Options:
  --yes, -y              Auto-run all core steps (no step prompts)
  --dry-run              Show steps only
  --log                  Tee orchestrator output to logs/fedora_rebuild.log
  --skip-mobsf           Do not offer/run MobSF install
  --skip-doctor          Skip final research_doctor.sh
  --skip-final-doctor    Alias for --skip-doctor
  --help, -h             Show this help

With --yes: auto-installs MobSF when compose is missing; runs research doctor at end.

Daily lane menus: ./fedora.sh
Preferred rebuild: ./fedora.sh --rebuild  (this script: compatibility wrapper + implementation)
See: docs/GETTING-STARTED.md
EOF
}

rebuild_mode_menu() {
  # shellcheck source=lib/menu.sh
  source "${FEDORA_ROOT}/lib/menu.sh"
  menu_init "Fedora Rebuild" "${FEDORA_ROOT}"

  _rebuild_mode_items() {
    menu_item 1 "Interactive (confirm each step)"
    menu_item 2 "Auto-yes (no prompts between steps)"
    menu_item 3 "Dry run (show steps only)"
    menu_item 4 "Interactive + log to fedora_rebuild.log"
    menu_item 5 "Auto-yes + log"
    menu_item 0 "Cancel"
  }

  _rebuild_mode_dispatch() {
    case "$1" in
      0) echo "Cancelled."; exit 0 ;;
      1) return 0 ;;
      2) AUTO_YES=1; return 0 ;;
      3) DRY_RUN=1; return 0 ;;
      4) USE_LOG=1; return 0 ;;
      5) AUTO_YES=1; USE_LOG=1; return 0 ;;
      *) return 2 ;;
    esac
  }

  menu_loop "Choose rebuild mode" \
    "5 core steps + optional MobSF + research doctor" \
    _rebuild_mode_items _rebuild_mode_dispatch
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) AUTO_YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --log) USE_LOG=1; shift ;;
    --skip-mobsf) SKIP_MOBSF=1; shift ;;
    --skip-doctor|--skip-final-doctor) SKIP_DOCTOR=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

if (( AUTO_YES == 0 && DRY_RUN == 0 && USE_LOG == 0 )) && [[ -t 0 ]] && [[ "${FEDORA_FROM_MENU:-}" != 1 ]]; then
  rebuild_mode_menu
fi

if [[ "${FEDORA_FROM_MENU:-}" == 1 ]]; then
  info "Rebuild from fedora.sh — confirm each step (no mode picker)"
fi

if (( USE_LOG )); then
  init_script_logging "${FEDORA_LOG_REBUILD}" "fedora_rebuild.sh" "Fedora Rebuild Sequence"
  (( DRY_RUN )) && log_warn "DRY RUN — no scripts will execute"
fi

REBUILD_TOTAL=5
(( SKIP_MOBSF )) || REBUILD_TOTAL=$(( REBUILD_TOTAL + 1 ))
(( SKIP_DOCTOR )) || REBUILD_TOTAL=$(( REBUILD_TOTAL + 1 ))
REBUILD_STEP=0
REBUILD_FAILED=0

run_step() {
  local title="$1"
  local rel="$2"
  shift 2
  local use_sudo=0
  local use_sudo_e=0
  local extra=()

  if [[ "${1:-}" == "--sudo" ]]; then use_sudo=1; shift; fi
  if [[ "${1:-}" == "--sudo-E" ]]; then use_sudo_e=1; shift; fi
  extra=("$@")

  REBUILD_STEP=$(( REBUILD_STEP + 1 ))

  echo
  echo "============================================================"
  echo "STEP [${REBUILD_STEP}/${REBUILD_TOTAL}]: ${title}"
  echo "Script: ${rel}"
  echo "============================================================"

  if (( USE_LOG )); then
    log_step "${REBUILD_STEP}" "${REBUILD_TOTAL}" "STEP: ${title} (${rel})"
  fi

  if (( DRY_RUN )); then
    info "(dry-run) would execute: ${rel} ${extra[*]:-}"
    if (( USE_LOG )); then
      log_info "(dry-run) would execute: ${rel} ${extra[*]:-}"
    fi
    return 0
  fi

  if (( AUTO_YES )) || confirm "Run this step?"; then
    local script="${FEDORA_ROOT}/${rel}"
    local rc=0
    assert_file "${script}" "Rebuild step script missing: ${rel}"
    if (( use_sudo_e )); then
      sudo -E bash "${script}" "${extra[@]}" || rc=$?
    elif (( use_sudo )); then
      sudo bash "${script}" "${extra[@]}" || rc=$?
    else
      bash "${script}" "${extra[@]}" || rc=$?
    fi
    if (( rc != 0 )); then
      warn "Step failed (exit ${rc}): ${title}"
      REBUILD_FAILED=$(( REBUILD_FAILED + 1 ))
      if (( USE_LOG )); then
        log_warn "Step failed: ${title} (exit ${rc})"
      fi
    else
      ok "Step complete: ${title}"
      if (( USE_LOG )); then
        log_info "Step complete: ${title}"
      fi
    fi
  else
    warn "Skipped: ${title}"
    if (( USE_LOG )); then
      log_warn "Skipped: ${title}"
    fi
  fi
}

maybe_mobsf_step() {
  (( SKIP_MOBSF )) && return 0

  # shellcheck source=lib/mobsf.sh
  source "${FEDORA_ROOT}/lib/mobsf.sh"

  if (( DRY_RUN )); then
    info "(dry-run) would offer: MobSF install/reset"
    return 0
  fi

  if (( AUTO_YES )); then
    if mobsf_compose_installed; then
      info "MobSF compose present — skipping auto install (reset manually if needed)"
      return 0
    fi
    run_step "MobSF install" "mobsf/mobsf_install.sh" --sudo-E
    return 0
  fi

  if confirm "Run MobSF install/reset? (install if first time; reset if stack exists)"; then
    if mobsf_compose_installed; then
      run_step "MobSF reset (keep data)" "mobsf/mobsf_reset.sh" --sudo-E --keep
    else
      run_step "MobSF install" "mobsf/mobsf_install.sh" --sudo-E
    fi
  fi
}

maybe_research_doctor() {
  (( SKIP_DOCTOR )) && return 0
  if (( DRY_RUN )); then
    info "(dry-run) would offer: research doctor"
    return 0
  fi
  if (( AUTO_YES )) || confirm "Run research doctor (Android + MobSF)?"; then
    run_step "Research doctor" "system/research_doctor.sh"
  fi
}

info "Fedora workstation rebuild sequence"
info "Root: ${FEDORA_ROOT}"
(( DRY_RUN )) && warn "DRY RUN — no scripts will execute"
(( USE_LOG )) && info "Logging to: $(log_file_path "${FEDORA_LOG_REBUILD}")"
echo "[NOTE] system_update.sh always logs to logs/system_update.log on its own."

run_step "System update" "system/system_update.sh" --sudo-E --quick
run_step "Containers + KVM" "dev/fedora_container_kvm_setup.sh" --sudo
run_step "Android core tools" "android/android_dev_core_setup.sh" --sudo
run_step "Install RE tools (all)" "android/android_re_install.sh" all
run_step "Verify all RE tools" "android/verify_re_tool.sh" all

maybe_mobsf_step
maybe_research_doctor

echo
if (( REBUILD_FAILED > 0 )); then
  warn "Rebuild finished with ${REBUILD_FAILED} failed step(s) — review output above"
else
  ok "Rebuild sequence finished"
fi
echo "[NEXT] source ~/.bashrc  OR  log out/in for PATH/group changes"
echo "[NEXT] ./fedora.sh  OR  ./android/android.sh  OR  ./mobsf.sh"
if (( USE_LOG )); then
  echo "[NEXT] ./system/log_engine.sh tail --file fedora_rebuild.log --lines 50"
fi
