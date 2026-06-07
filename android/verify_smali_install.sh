#!/usr/bin/env bash
# verify_smali_install.sh — Shim → verify_re_tool.sh smali
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/verify_re_tool.sh" smali "$@"
