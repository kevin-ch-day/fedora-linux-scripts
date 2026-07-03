#!/usr/bin/env bash
# fedora.sh — compatibility redirect → ./run.sh
# Version: 0.2.0
#
# Prefer: ./run.sh

set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${ROOT}/run.sh" "$@"
