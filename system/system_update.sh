#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Filename: system_update.sh
# Purpose : Fedora system update + cleanup (deterministic, ops-grade)
# Version : 0.6.0
#
# Run:
#   sudo ./system/system_update.sh
#   sudo ./system/system_update.sh --quick
#   sudo ./system/system_update.sh --help
#
# Logging:
#   Engine: lib/logging.sh — logs/system_update.log
#   Env: FEDORA_LOG_LEVEL=DEBUG  FEDORA_LOG_ROTATE_MB=10 (default: 10)
# ============================================================

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/packages.sh
source "${_SCRIPT_DIR}/../lib/packages.sh"
# shellcheck source=../lib/health.sh
source "${_SCRIPT_DIR}/../lib/health.sh"
# shellcheck source=../lib/logging.sh
source "${_SCRIPT_DIR}/../lib/logging.sh"

QUICK=0
UPDATE_ISSUES=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Full Fedora update: refresh metadata, upgrade, distro-sync, autoremove,
clean caches, prune old kernels, rpm verify, reboot check, health snapshot.

Always logs to logs/system_update.log (logging engine v0.3).

Options:
  --quick            Skip slow rpm -Va verify (steps 8 still runs health snapshot)
  --help, -h         Show this help

Environment:
  FEDORA_LOG_LEVEL=DEBUG|INFO|WARN|ERROR   (default: INFO)
  FEDORA_LOG_ROTATE_MB=N                   (default: 10, 0=off)

Run with sudo.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --quick) QUICK=1; shift ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
done

require_root "Run with sudo: sudo ./system/system_update.sh"
FEDORA_LOG_ROTATE_MB="${FEDORA_LOG_ROTATE_MB:-10}"
errors_init_script "system_update.sh"
init_script_logging "${FEDORA_LOG_SYSTEM_UPDATE}" "system_update.sh" "Fedora System Update"

packages_preflight
wait_for_dnf_lock

log_step 1 10 "Refreshing metadata..."
require_ok "dnf makecache failed" dnf_makecache_refresh

echo
log_step 2 10 "Showing available updates (summary)..."
dnf_show_updates

echo
log_step 3 10 "Applying updates (dnf upgrade)..."
require_ok "dnf upgrade failed" dnf_upgrade

echo
log_step 4 10 "Syncing distro packages (dnf distro-sync)..."
if ! dnf_distro_sync; then
  warn "dnf distro-sync reported issues — review output above"
  UPDATE_ISSUES=$((UPDATE_ISSUES + 1))
fi

echo
log_step 5 10 "Removing unneeded dependencies (dnf autoremove)..."
require_ok "dnf autoremove failed" dnf_autoremove

echo
log_step 6 10 "Cleaning DNF caches..."
require_ok "dnf clean failed" dnf_clean_all

echo
log_step 7 10 "Pruning old kernels (keeping latest 3)..."
if ! kernel_prune_keep3; then
  warn "Kernel prune reported issues — review output above"
  UPDATE_ISSUES=$((UPDATE_ISSUES + 1))
fi

echo
log_step 8 10 "RPM verification report..."
if (( QUICK )); then
  log_info "Skipped rpm -Va (--quick)"
else
  rpm_verify_report 200 180
fi

echo
log_step 9 10 "Sanity check for dependency issues..."
if dnf_check; then
  log_info "dnf check: OK"
else
  log_warn "dnf check: FAILED — inspect output above"
  UPDATE_ISSUES=$((UPDATE_ISSUES + 1))
fi

echo
log_step 10 10 "Summary + reboot guidance"
log_info "Tip: Review changes with: dnf history info last"
needs_reboot_check
health_post_update_snapshot

packages_fix_repo_permissions

echo
if (( UPDATE_ISSUES == 0 )); then
  log_info "Update run complete — no soft-fail steps"
else
  log_warn "Update run complete — ${UPDATE_ISSUES} soft-fail step(s); see log above"
fi
log_info "Done."
echo
log_info "Full log: ${LOG_FILE}"
log_info "Next: ./fedora.sh --rebuild-check  (System → Maintenance → [5])"

exit $(( UPDATE_ISSUES > 0 ? 1 : 0 ))
