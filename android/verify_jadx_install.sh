#!/usr/bin/env bash
# verify_jadx_install.sh — Shim → verify_re_tool.sh jadx
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/verify_re_tool.sh" jadx "$@"
