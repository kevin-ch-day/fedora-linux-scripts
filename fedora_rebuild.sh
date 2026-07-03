#!/usr/bin/env bash
# fedora_rebuild.sh — compatibility redirect → ./run.sh --rebuild
# Version: 0.6.0
#
# Prefer: ./run.sh --rebuild  ·  ./install.sh research --yes

set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${ROOT}/run.sh" --rebuild "$@"
