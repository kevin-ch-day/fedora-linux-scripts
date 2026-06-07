#!/usr/bin/env bash
# verify_dex2jar_install.sh — Shim → verify_re_tool.sh dex2jar
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/verify_re_tool.sh" dex2jar "$@"
