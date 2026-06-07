#!/usr/bin/env bash
# view_logs.sh — DEPRECATED shim → log_engine.sh (legacy flags via lib/logging.sh)
# Version: 0.5.0
#
# Prefer: ./system/log_engine.sh tail --file NAME --lines N

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/logging.sh
source "${_SCRIPT_DIR}/../lib/logging.sh"

if [[ -t 2 ]]; then
  echo "[DEPRECATED] view_logs.sh — use: ./system/log_engine.sh (see CONSOLIDATION.md)" >&2
fi

logging_view_logs_legacy "${_SCRIPT_DIR}/log_engine.sh" "$@"
