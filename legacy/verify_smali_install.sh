#!/usr/bin/env bash
# DEPRECATED — duplicate of ../android/verify_smali_install.sh.
# Use: ./android/verify_smali_install.sh
# Moved to legacy/ during repo cleanup (2026-06).

echo "[DEPRECATED] Disabled. Use: ../android/verify_smali_install.sh" >&2
exit 1

#
# verify_smali_install.sh
# Quick verification for smali/baksmali user-scope install
# Version: 0.2.0
#
# Run:
#   ./verify_smali_install.sh

set -euo pipefail

# Do NOT source ~/.bashrc (Fedora's /etc/bashrc can break under non-interactive "nounset" cases).
# Just ensure user-local bin is available for this check.
export PATH="$HOME/.local/bin:$PATH"

echo "== smali =="
command -v smali >/dev/null 2>&1 || { echo "[ERROR] smali not found on PATH"; exit 2; }
smali --version

echo "== baksmali =="
command -v baksmali >/dev/null 2>&1 || { echo "[ERROR] baksmali not found on PATH"; exit 2; }
baksmali --version

echo "== paths =="
command -v smali baksmali

echo "== jars =="
ls -lh "$HOME/.local/opt/smali/"*.jar

echo "== OK =="

