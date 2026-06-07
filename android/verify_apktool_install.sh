#!/usr/bin/env bash
# verify_apktool_install.sh — Shim → verify_re_tool.sh apktool
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/verify_re_tool.sh" apktool "$@"
