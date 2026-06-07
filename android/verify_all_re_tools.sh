#!/usr/bin/env bash
# verify_all_re_tools.sh — Shim → verify_re_tool.sh all
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/verify_re_tool.sh" all "$@"
