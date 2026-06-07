#!/usr/bin/env bash
# android_re_dex2jar_user_install.sh — Shim → android_re_install.sh dex2jar
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/android_re_install.sh" dex2jar "$@"
