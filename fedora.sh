#!/usr/bin/env bash
# fedora.sh — compatibility wrapper for ./run.sh (older docs and scripts)
# Version: 0.1.0
#
# Prefer: ./run.sh

set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${ROOT}/run.sh" "$@"
