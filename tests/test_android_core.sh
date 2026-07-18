#!/usr/bin/env bash
# Android core helper regressions. No installs, sudo, or host writes.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/android/android_dev_core_setup.sh"
TESTS=0

pass() {
  TESTS=$((TESTS + 1))
  printf '[OK]   %s\n' "$1"
}

fail() {
  printf '[ERROR] %s\n' "$1" >&2
  exit 1
}

(
  set --
  FEDORA_ANDROID_CORE_LIB_ONLY=1
  # shellcheck disable=SC1090
  source "${SCRIPT}"

  sandbox="$(mktemp -d)"
  trap 'rm -rf "${sandbox}"' EXIT
  REAL_HOME="${sandbox}/home"
  ANDROID_SDK_DIR="${REAL_HOME}/Android/Sdk"
  mkdir -p "${REAL_HOME}"
  printf '# existing shell configuration\n' > "${REAL_HOME}/.bashrc"

  _write_bashrc_android_sdk_paths
  grep -qF '# existing shell configuration' "${REAL_HOME}/.bashrc"
  grep -qF '# >>> ANDROID SDK PATHS (managed) >>>' "${REAL_HOME}/.bashrc"
  grep -qF 'export ANDROID_HOME="$HOME/Android/Sdk"' "${REAL_HOME}/.bashrc"
) || fail "managed Android shell block is not copyable by its owner"
pass "managed Android shell block is copyable by its owner"

(
  set --
  FEDORA_ANDROID_CORE_LIB_ONLY=1
  # shellcheck disable=SC1090
  source "${SCRIPT}"

  calls="$(mktemp)"
  trap 'rm -f "${calls}"' EXIT
  pkg_present() { return 0; }
  flatpak() {
    if [[ "${1:-}" == remotes && "${2:-}" == "--columns=name" ]]; then
      printf 'fedora\n'
      return 0
    fi
    if [[ "${1:-}" == remotes && "${2:-}" == "--show-disabled" ]]; then
      printf 'fedora\nflathub\n'
      return 0
    fi
    if [[ "${1:-}" == remote-modify && "${2:-}" == "--enable" && "${3:-}" == flathub ]]; then
      printf '%s\n' "$*" >> "${calls}"
      return 0
    fi
    return 1
  }

  flatpak_ensure_flathub
  grep -qF 'remote-modify --enable flathub' "${calls}"
) || fail "disabled Flathub remote is not enabled"
pass "disabled Flathub remote is enabled before install"

printf '[OK]   Android core helper regressions passed (%s)\n' "${TESTS}"
