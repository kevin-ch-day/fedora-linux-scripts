#!/usr/bin/env bash
# mobsf_update.sh — Pull latest MobSF images and run DB migrations
# Version: 0.1.1
#
# Run: sudo -E ./mobsf/mobsf_update.sh

set -euo pipefail

MOBSF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${MOBSF_DIR}/.." && pwd)"
# shellcheck source=lib/mobsf.sh
source "${MOBSF_DIR}/lib/mobsf.sh"
# shellcheck source=../lib/logging.sh
source "${FEDORA_ROOT}/lib/logging.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      echo "Usage: $(basename "$0")"
      echo "Pull latest images, run migrate.sh, restart stack."
      echo "Run with: sudo -E $0"
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
done

require_root "Run with: sudo -E ./mobsf/mobsf_update.sh"
init_script_logging "${FEDORA_LOG_MOBSF}" "mobsf_update.sh" "MobSF update"

mobsf_require_tools
mobsf_compose_cd || die "Compose dir not found"
mobsf_compose_validate "${MOBSF_COMPOSE_FILE}"

mobsf_stack_pull
info "Stopping stack for migration..."
mobsf_stack_down
info "Starting postgres for migration..."
require_ok "Postgres container start failed" \
  mobsf_pc_action "Postgres container start" up -d postgres
mobsf_wait_postgres >/dev/null
info "Running database migrations..."
require_ok "MobSF migrate failed — try: sudo -E ./mobsf/mobsf_reset.sh --keep" \
  mobsf_pc_action "MobSF database migration" run --rm --no-deps mobsf \
    /home/mobsf/Mobile-Security-Framework-MobSF/scripts/migrate.sh

info "Restarting stack..."
mobsf_stack_up_ordered
ok "MobSF update complete"
