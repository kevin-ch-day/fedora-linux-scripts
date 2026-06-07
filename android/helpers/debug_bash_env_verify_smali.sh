#!/usr/bin/env bash
# debug_bash_env_verify_smali.sh — Diagnose BASH_ENV issues with smali verify
# Version: 0.1.1
#
# Run:
#   ./android/helpers/debug_bash_env_verify_smali.sh
#   ./android/helpers/debug_bash_env_verify_smali.sh --help

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [--help]

Print BASH_ENV / SHELLOPTS and locate verify_smali_install.sh in cwd.
Run from android/ if checking the verify shim.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    *) echo "[ERROR] Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

echo "== [1] Environment signals (BASH_ENV / SHELLOPTS) =="
echo "BASH_ENV=${BASH_ENV-<unset>}"
env | grep -E '^(BASH_ENV|SHELLOPTS)=' || true
echo

echo "== [2] Location + target script sanity =="
pwd
if [[ -f "verify_smali_install.sh" ]]; then
  ls -l verify_smali_install.sh
  echo
  echo "== First 30 lines of verify_smali_install.sh =="
  head -n 30 verify_smali_install.sh | nl -ba
else
  echo "[WARN] verify_smali_install.sh not found in current directory."
  echo "[HINT] cd android/ && ./helpers/$(basename "$0")"
fi
