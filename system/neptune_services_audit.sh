#!/usr/bin/env bash
# Deprecated wrapper — use ./system/hardening_services_audit.sh
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hardening_services_audit.sh" "$@"
