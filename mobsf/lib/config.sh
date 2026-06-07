#!/usr/bin/env bash
# mobsf/lib/config.sh — MobSF constants and defaults
# Do not execute directly.

MOBSF_UI_URL="${MOBSF_UI_URL:-http://127.0.0.1:8080/}"
MOBSF_LOGIN_URL="${MOBSF_LOGIN_URL:-http://127.0.0.1:8080/login/}"
MOBSF_BUNDLE_DIR="${MOBSF_BUNDLE_DIR:-$(cd -- "${_MOBSF_LIB_DIR}/.." && pwd)}"
