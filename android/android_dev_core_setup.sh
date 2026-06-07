#!/usr/bin/env bash
# android_dev_core_setup.sh
# Android dev + security core setup (Fedora)
# Version: 0.6.2
#
# Stable installs only:
# - dnf: Java 21, adb/fastboot, python3/pip, nodejs(+nodejs-npm), wireshark, flatpak, unzip/curl
# - flatpak: Android Studio (optional)
# - pip (user): frida-tools, objection, drozer, mitmproxy
# - Android SDK cmdline-tools + PATH
#
# Run: sudo ./android_dev_core_setup.sh
#      sudo ./android_dev_core_setup.sh --help

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/packages.sh
source "${_SCRIPT_DIR}/../lib/packages.sh"
# shellcheck source=../lib/logging.sh
source "${_SCRIPT_DIR}/../lib/logging.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--help]

Install Android dev + security core for $(real_user):
  Java 21, adb/fastboot, Python/pip tools, Node/npm, Wireshark, SDK cmdline-tools,
  user-scoped pip (frida-tools, objection, mitmproxy, …), optional Android Studio flatpak.

Logs to: logs/android_dev_core.log

Run with sudo: sudo ./android/android_dev_core_setup.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

REAL_HOME="$(real_home)"

# ---------- pip helpers (user scope only) ----------
pip_user_upgrade_tools() {
  have python3 || return 0
  have pip3 || { warn "pip3 not found; skipping pip upgrades"; return 0; }
  run_as_real_user python3 -m pip install --user --upgrade pip setuptools wheel >/dev/null
  ok "pip user tools upgraded (pip/setuptools/wheel)"
}

pip_user_install() {
  local pkg="$1"
  have python3 || { warn "python3 not installed; skipping: ${pkg}"; return 0; }
  have pip3 || { warn "pip3 not installed; skipping: ${pkg}"; return 0; }
  run_as_real_user python3 -m pip install --user --upgrade "$pkg" >/dev/null
  ok "pip user install: ${pkg}"
}

# ---------- flatpak helpers ----------
flatpak_ensure_flathub() {
  have flatpak || return 0
  if flatpak remotes | awk '{print $1}' | grep -qx flathub; then
    ok "Flatpak flathub already configured"
  else
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo >/dev/null
    ok "Flatpak flathub added"
  fi
}

flatpak_install_optional() {
  local ref="$1"
  have flatpak || { warn "flatpak not installed; skipping ${ref}"; return 0; }
  if flatpak info "$ref" >/dev/null 2>&1; then
    ok "Flatpak already installed: ${ref}"
    return 0
  fi
  flatpak install -y --noninteractive flathub "$ref" >/dev/null \
    && ok "Flatpak installed: ${ref}" \
    || warn "Flatpak install failed: ${ref}"
}

# ---------- Android SDK helpers ----------
install_android_cmdline_tools() {
  local sdk_dir="${REAL_HOME}/Android/Sdk"
  local tools_dir="${sdk_dir}/cmdline-tools"
  local latest_dir="${tools_dir}/latest"

  run_as_real_user mkdir -p "${tools_dir}"
  if [[ -d "${latest_dir}" ]] && [[ -x "${latest_dir}/bin/sdkmanager" ]]; then
    ok "Android SDK cmdline-tools already present"
    return 0
  fi

  info "Installing Android SDK command-line tools into: ${latest_dir}"
  run_as_real_user bash -c "
set -euo pipefail
tmp=\$(mktemp -d)
trap 'rm -rf \"\${tmp}\"' EXIT
zip=\"\${tmp}/cmdline-tools.zip\"
curl -L --fail --retry 3 --retry-delay 2 -o \"\${zip}\" \
  'https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip'
mkdir -p \"\${tmp}/extract\"
unzip -q \"\${zip}\" -d \"\${tmp}/extract\"
rm -rf '${latest_dir}'
mkdir -p '${latest_dir}'
mv \"\${tmp}/extract/cmdline-tools/\"* '${latest_dir}/'
"
  chown -R "$(real_user):$(real_user)" "${sdk_dir}" 2>/dev/null || true
  ok "Android SDK cmdline-tools installed"
}

ensure_android_paths_in_bashrc() {
  local bashrc="${REAL_HOME}/.bashrc"
  local marker_begin="# >>> ANDROID SDK PATHS (managed) >>>"
  local marker_end="# <<< ANDROID SDK PATHS (managed) <<<"

  if [[ -f "${bashrc}" ]] && grep -qF "${marker_begin}" "${bashrc}"; then
    ok "Android SDK PATH block already present in ${bashrc}"
    return 0
  fi

  info "Adding Android SDK PATH block to ${bashrc}"
  cat >> "${bashrc}" <<EOF

${marker_begin}
export ANDROID_HOME="\$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="\$HOME/Android/Sdk"
export PATH="\$PATH:\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools"
${marker_end}
EOF

  chown "$(real_user):$(real_user)" "${bashrc}" 2>/dev/null || true
  ok "Android SDK PATH block added"
}

# ---------- Main ----------
require_root
init_script_logging "${FEDORA_LOG_ANDROID_CORE}" "android_dev_core_setup.sh" "Android dev core setup"
MISSING_PKGS=()

info "Android dev + security CORE setup (Fedora)"
info "Invoker user: $(real_user) (home: ${REAL_HOME})"
echo

ensure_user_bin_on_path

info "Installing core packages (dnf)..."
pkg_install_batch_if_available MISSING_PKGS \
  java-21-openjdk \
  java-21-openjdk-devel \
  android-tools \
  python3 \
  python3-pip \
  wireshark \
  flatpak \
  curl \
  unzip \
  nodejs \
  nodejs-npm
echo

info "Installing Android Studio (Flatpak, optional)..."
flatpak_ensure_flathub
flatpak_install_optional com.google.AndroidStudio
echo

info "Installing Python mobile tooling (pip user scope)..."
pip_user_upgrade_tools
pip_user_install frida-tools
pip_user_install objection
pip_user_install drozer || true
pip_user_install mitmproxy || true
echo

info "Installing Node global tooling (apk-mitm, optional)..."
if have npm; then
  if run_as_real_user npm -g list apk-mitm >/dev/null 2>&1; then
    ok "apk-mitm already installed globally"
  else
    run_as_real_user npm install -g apk-mitm >/dev/null \
      && ok "apk-mitm installed globally" \
      || warn "apk-mitm install failed"
  fi
else
  warn "npm command not found (nodejs-npm may be missing). Skipping apk-mitm."
fi
echo

info "Installing Android SDK cmdline-tools + PATH..."
install_android_cmdline_tools
ensure_android_paths_in_bashrc
echo

ok "CORE setup complete!"
echo "[NEXT] source ~/.bashrc (or restart shell)"
echo

if ((${#MISSING_PKGS[@]} > 0)); then
  warn "Packages not available in enabled repos:"
  printf '  - %s\n' "${MISSING_PKGS[@]}"
  echo
fi

echo "Optional RE tools are now in separate scripts:"
echo "  - android_re_apktool_user_install.sh"
echo "  - android_re_jadx_user_install.sh"
echo "  - android_re_smali_user_install.sh"
echo "  - android_re_dex2jar_user_install.sh"
echo
echo "Quick checks:"
echo "  adb version"
echo "  java -version"
echo "  sdkmanager --version"
echo "  frida --version"
echo "  objection --version"
echo "  mitmproxy --version"
