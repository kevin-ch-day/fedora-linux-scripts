#!/usr/bin/env bash
# rebuild_readiness_check.sh — pre-rebuild readiness (no installs, no changes)
# Version: 0.2.0
#
# Run:
#   ./system/rebuild_readiness_check.sh
#   ./fedora.sh --rebuild-check

set -uo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${_SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/baseline.sh
source "${FEDORA_ROOT}/lib/baseline.sh"
# shellcheck source=../lib/theme.sh
source "${FEDORA_ROOT}/lib/theme.sh"
theme_init

usage() {
  cat <<EOF
Usage: $(basename "$0") [--help]

Lightweight checks before ./fedora.sh --rebuild.
Does not install packages or modify the system.

Also: ./fedora.sh --rebuild-check

Recommended flow on a new machine:
  ./fedora.sh --doctor
  ./fedora.sh --baseline
  ./fedora.sh --rebuild-check
  ./fedora.sh --rebuild

Toolkit root: ${FEDORA_ROOT}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

ISSUES=0
PASSES=0
MIN_ROOT_MB=2048

_check() {
  local label="$1"
  local ok_msg="$2"
  shift 2
  if "$@"; then
    ok "${label}: ${ok_msg}"
    PASSES=$((PASSES + 1))
  else
    warn "${label}: FAILED"
    ISSUES=$((ISSUES + 1))
  fi
}

theme_init
theme_set_lane rebuild

theme_report_header "Rebuild readiness check" \
  "Host: $(health_hostname) · User: $(real_user)" \
  "Toolkit root: ${FEDORA_ROOT}"

_check "Fedora detected" "$(baseline_fedora_release_line)" baseline_is_fedora

if [[ -d "${FEDORA_ROOT}" && -f "${FEDORA_ROOT}/fedora.sh" ]]; then
  ok "Repo root: ${FEDORA_ROOT}"
  PASSES=$((PASSES + 1))
else
  warn "Repo root: FAILED (expected fedora.sh at ${FEDORA_ROOT})"
  ISSUES=$((ISSUES + 1))
fi

if [[ -x "${FEDORA_ROOT}/fedora.sh" ]]; then
  ok "fedora.sh: executable"
  PASSES=$((PASSES + 1))
else
  warn "fedora.sh: FAILED (not executable)"
  ISSUES=$((ISSUES + 1))
fi

if baseline_ping_ok 1.1.1.1 1; then
  ok "Network: reachable (ping 1.1.1.1)"
  PASSES=$((PASSES + 1))
else
  warn "Network: FAILED (ping 1.1.1.1)"
  ISSUES=$((ISSUES + 1))
fi

if baseline_dnf_check_ok; then
  ok "dnf check: OK"
  PASSES=$((PASSES + 1))
else
  _unreadable="$(baseline_unreadable_repo_files | tr '\n' ' ' | sed 's/ $//' || true)"
  if [[ -n "${_unreadable}" ]] && baseline_try_fix_dnf_repos "${FEDORA_ROOT}"; then
    ok "dnf check: OK (auto-fixed repo permissions)"
    PASSES=$((PASSES + 1))
  else
    warn "dnf check: FAILED"
    _dnf_check_err="$(dnf check 2>&1 | head -n 2 || true)"
    if [[ -n "${_dnf_check_err}" ]]; then
      info "  ${_dnf_check_err//$'\n'/ · }"
    fi
    if [[ -n "${_unreadable}" ]]; then
      info "  Unreadable repo files: ${_unreadable}"
      info "  Fix: sudo ./fedora.sh --fix-repos"
      info "       or System → [7] Cleanup → [6] Fix DNF repo permissions"
    else
      info "  Fix: System → [4] Update Fedora  (or: sudo dnf check)"
    fi
    ISSUES=$((ISSUES + 1))
  fi
fi

if baseline_is_uefi; then
  ok "UEFI: yes (/sys/firmware/efi present)"
  PASSES=$((PASSES + 1))
else
  info "UEFI: no (legacy BIOS — not a blocker for rebuild)"
fi

root_avail="$(baseline_root_avail_mb)"
root_pct="$(baseline_root_use_pct)"
if [[ "${root_avail}" =~ ^[0-9]+$ ]] && (( root_avail >= MIN_ROOT_MB )); then
  ok "Root free space: ${root_avail} MiB available (${root_pct}% used on /)"
  PASSES=$((PASSES + 1))
else
  warn "Root free space: FAILED (${root_avail} MiB free; want >= ${MIN_ROOT_MB} MiB, ${root_pct}% used)"
  ISSUES=$((ISSUES + 1))
fi

if baseline_sudo_available; then
  ok "sudo: available (rebuild will prompt when needed)"
  PASSES=$((PASSES + 1))
else
  warn "sudo: FAILED (not installed — rebuild requires sudo)"
  ISSUES=$((ISSUES + 1))
fi

if baseline_toolkit_lane_dirs_ok "${FEDORA_ROOT}"; then
  ok "Lane directories: system dev android lib logs present"
  PASSES=$((PASSES + 1))
else
  warn "Lane directories: FAILED (incomplete repo checkout?)"
  ISSUES=$((ISSUES + 1))
fi

if [[ -d "$(log_dir)" ]]; then
  ok "logs directory: $(log_dir)"
  PASSES=$((PASSES + 1))
else
  warn "logs directory: FAILED (missing $(log_dir))"
  ISSUES=$((ISSUES + 1))
fi

if (( ISSUES == 0 )); then
  theme_summary_box "Summary" \
    "Result:     READY" \
    "Passed:     ${PASSES} check(s)" \
    "Failed:     0" \
    "Next step:  ./fedora.sh --rebuild"
  exit 0
fi

theme_summary_box "Summary" \
  "Result:     NOT READY" \
  "Passed:     ${PASSES} check(s)" \
  "Failed:     ${ISSUES} check(s)" \
  "Next step:  fix issues above, then ./fedora.sh --rebuild-check" \
  "            when ready: ./fedora.sh --rebuild"
exit 1
