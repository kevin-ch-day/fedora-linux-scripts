#!/usr/bin/env bash
# android_re_smali_user_install.sh — Shim → android_re_install.sh smali
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/android_re_install.sh" smali "$@"
