#!/usr/bin/env bash
# Deprecated wrapper — use ./system/hardening_round1.sh
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hardening_round1.sh" "$@"
