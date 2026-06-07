#!/usr/bin/env bash
# android_re_install.sh — Install Android RE tools (user scope)
# Version: 0.2.0
#
# Run:
#   ./android/android_re_install.sh apktool
#   ./android/android_re_install.sh all
#   ./android/android_re_install.sh --help

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/android_re.sh
source "${_SCRIPT_DIR}/../lib/android_re.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") TOOL [--help]

Install user-scope RE tools to ~/.local/:
  apktool | jadx | smali | dex2jar | all

Legacy per-tool wrappers: android_re_*_user_install.sh
EOF
}

TOOL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    apktool|jadx|smali|dex2jar|all) TOOL="$1"; shift ;;
    *) die "Unknown option or tool: $1 (try --help)" ;;
  esac
done

[[ -n "${TOOL}" ]] || { usage >&2; exit 2; }

case "${TOOL}" in
  apktool) android_re_install_apktool ;;
  jadx) android_re_install_jadx ;;
  smali) android_re_install_smali ;;
  dex2jar) android_re_install_dex2jar ;;
  all) android_re_install_all ;;
esac
