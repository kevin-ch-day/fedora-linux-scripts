#!/usr/bin/env bash
# android_re_apktool_user_install.sh — Shim → android_re_install.sh apktool
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/android_re_install.sh" apktool "$@"
