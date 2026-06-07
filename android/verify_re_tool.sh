#!/usr/bin/env bash
# verify_re_tool.sh — Verify one or all Android RE tools (user scope)
# Version: 0.1.0
#
# Run:
#   ./android/verify_re_tool.sh apktool
#   ./android/verify_re_tool.sh all
#   ./android/verify_re_tool.sh --help

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/android.sh
source "${_SCRIPT_DIR}/../lib/android.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") TOOL [--help]

Tools:
  apktool    Verify apktool (~/.local/opt/apktool)
  jadx       Verify jadx / jadx-gui
  smali      Verify smali/baksmali
  dex2jar    Verify d2j-* tools
  all        Run all four verifiers (same as verify_all_re_tools.sh)

Legacy shims: verify_apktool_install.sh, verify_jadx_install.sh, etc.
EOF
}

TOOL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    apktool|jadx|smali|dex2jar|all) TOOL="$1"; shift ;;
    *)
      die "Unknown option or tool: $1 (try --help)"
      ;;
  esac
done

[[ -n "${TOOL}" ]] || { usage >&2; exit 2; }

case "${TOOL}" in
  apktool) android_verify_apktool ;;
  jadx) android_verify_jadx ;;
  smali) android_verify_smali ;;
  dex2jar) android_verify_dex2jar ;;
  all) android_verify_all_re_tools ;;
esac
