#!/usr/bin/env bash
# inspect.sh — non-mutating Fedora host inventory
# Version: 0.1.0

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="${PYTHON:-python3}"

if ! command -v "${PYTHON}" >/dev/null 2>&1; then
  printf 'error: %s is required for host inspection\n' "${PYTHON}" >&2
  exit 127
fi

exec "${PYTHON}" "${ROOT}/libexec/inspect_host.py" "$@"
