#!/usr/bin/env bash
# android_dev_core_setup.sh
# Android dev + security core setup (Fedora)
# Version: 0.6.2
#
# Stable installs only:
# - dnf: available OpenJDK + Node.js packages, adb/fastboot, python3/pip, wireshark, flatpak, unzip/curl
# - flatpak: Android Studio (optional)
# - pip (user): frida-tools, objection, drozer, mitmproxy
# - Android SDK cmdline-tools + PATH
#
# Run: sudo ./android_dev_core_setup.sh
#      sudo ./android_dev_core_setup.sh --status
#      sudo ./android_dev_core_setup.sh --repair-node

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/packages.sh
source "${_SCRIPT_DIR}/../lib/packages.sh"
# shellcheck source=../lib/logging.sh
source "${_SCRIPT_DIR}/../lib/logging.sh"
# shellcheck source=../lib/theme.sh
source "${_SCRIPT_DIR}/../lib/theme.sh"
# shellcheck source=../lib/android.sh
source "${_SCRIPT_DIR}/../lib/android.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--help|--status|--repair-node]

Install Android dev + security core for $(real_user):
  OpenJDK, adb/fastboot, Python/pip tools, Node/npm, Wireshark, SDK cmdline-tools,
  user-scoped pip (frida-tools, objection, mitmproxy, …), optional Android Studio flatpak.

Logs to: logs/android_dev_core.log

Run with sudo: sudo ./android/android_dev_core_setup.sh
EOF
}

STATUS_ONLY=0
REPAIR_NODE_ONLY=0
QUIET_TERMINAL=0
declare -a CORE_WARNINGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --status) STATUS_ONLY=1; shift ;;
    --repair-node) REPAIR_NODE_ONLY=1; shift ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

REAL_HOME="$(real_home)"
if [[ "${FEDORA_ANDROID_MENU_MODE:-0}" == 1 && "${FEDORA_VERBOSE:-0}" != 1 ]]; then
  QUIET_TERMINAL=1
  export FEDORA_LOG_TERMINAL_BANNER=0
fi

run_as_real_user_with_path() {
  local userbin
  userbin="${REAL_HOME}/.local/bin"
  run_as_real_user env "HOME=${REAL_HOME}" "PATH=${userbin}:${PATH}" "$@"
}

quiet_run() {
  if (( QUIET_TERMINAL )) && [[ -n "${LOG_FILE:-}" ]]; then
    "$@" >> "${LOG_FILE}" 2>&1
  else
    "$@"
  fi
}

core_warn() {
  CORE_WARNINGS+=("$1")
  warn "$1"
}

pkg_available_exact() {
  dnf -q list --available "$1" >/dev/null 2>&1
}

append_if_available() {
  local array_name="$1"
  local pkg="$2"
  local -n arr_ref="${array_name}"
  pkg_available_exact "${pkg}" && arr_ref+=("${pkg}")
}

append_if_present_or_available() {
  local array_name="$1"
  local pkg="$2"
  local bin="${3:-${pkg}}"
  local -n arr_ref="${array_name}"
  if pkg_present "${pkg}" "${bin}" || pkg_available_exact "${pkg}"; then
    arr_ref+=("${pkg}")
  fi
}

resolve_java_packages() {
  local chosen=()

  if cmd_available java; then
    if cmd_available javac; then
      printf '%s\n' "${chosen[@]}"
      return 0
    fi
    if pkg_available_exact java-25-openjdk-devel; then
      chosen+=(java-25-openjdk-devel)
    elif pkg_available_exact java-latest-openjdk-devel; then
      chosen+=(java-latest-openjdk-devel)
    elif pkg_available_exact java-21-openjdk-devel; then
      chosen+=(java-21-openjdk-devel)
    fi
    printf '%s\n' "${chosen[@]}"
    return 0
  fi

  if pkg_present java-25-openjdk java; then
    chosen+=(java-25-openjdk)
    append_if_present_or_available chosen java-25-openjdk-devel javac
    printf '%s\n' "${chosen[@]}"
    return 0
  fi

  if pkg_present java-21-openjdk java; then
    chosen+=(java-21-openjdk)
    append_if_present_or_available chosen java-21-openjdk-devel javac
    printf '%s\n' "${chosen[@]}"
    return 0
  fi

  if pkg_available_exact java-25-openjdk; then
    chosen+=(java-25-openjdk)
    append_if_available chosen java-25-openjdk-devel
  elif pkg_available_exact java-latest-openjdk; then
    chosen+=(java-latest-openjdk)
    append_if_available chosen java-latest-openjdk-devel
  fi

  printf '%s\n' "${chosen[@]}"
}

resolve_node_packages() {
  local chosen=()

  if cmd_available node; then
    if cmd_available npm; then
      printf '%s\n' "${chosen[@]}"
      return 0
    fi
    if pkg_available_exact nodejs24-npm-bin; then
      chosen+=(nodejs24-npm nodejs24-npm-bin)
    elif pkg_available_exact nodejs22-npm-bin; then
      chosen+=(nodejs22-npm nodejs22-npm-bin)
    elif pkg_available_exact nodejs20-npm-bin; then
      chosen+=(nodejs20-npm nodejs20-npm-bin)
    elif pkg_available_exact nodejs-npm; then
      chosen+=(nodejs-npm)
    fi
    printf '%s\n' "${chosen[@]}"
    return 0
  fi

  if pkg_present nodejs node && pkg_present nodejs-npm npm; then
    chosen+=(nodejs)
    append_if_present_or_available chosen nodejs-npm npm
    printf '%s\n' "${chosen[@]}"
    return 0
  fi

  if pkg_available_exact nodejs24; then
    chosen+=(nodejs24)
    append_if_available chosen nodejs24-bin
    append_if_available chosen nodejs24-npm
    append_if_available chosen nodejs24-npm-bin
  elif pkg_available_exact nodejs22; then
    chosen+=(nodejs22)
    append_if_available chosen nodejs22-bin
    append_if_available chosen nodejs22-npm
    append_if_available chosen nodejs22-npm-bin
  elif pkg_available_exact nodejs20; then
    chosen+=(nodejs20)
    append_if_available chosen nodejs20-bin
    append_if_available chosen nodejs20-npm
    append_if_available chosen nodejs20-npm-bin
  fi

  printf '%s\n' "${chosen[@]}"
}

# ---------- pip helpers (user scope only) ----------
pip_user_upgrade_tools() {
  pkg_present python3 python3 || return 0
  pkg_present python3-pip pip3 || { core_warn "pip3 not found; skipping pip upgrades"; return 0; }
  quiet_run run_as_real_user_with_path python3 -m pip install --user --upgrade pip setuptools wheel
  ok "pip user tools upgraded (pip/setuptools/wheel)"
}

pip_user_install() {
  local pkg="$1"
  pkg_present python3 python3 || { core_warn "python3 not installed; skipping: ${pkg}"; return 0; }
  pkg_present python3-pip pip3 || { core_warn "pip3 not installed; skipping: ${pkg}"; return 0; }
  quiet_run run_as_real_user_with_path python3 -m pip install --user --upgrade "$pkg"
  ok "pip user install: ${pkg}"
}

# ---------- flatpak helpers ----------
flatpak_ensure_flathub() {
  pkg_present flatpak flatpak || return 0
  if flatpak remotes | awk '{print $1}' | grep -qx flathub; then
    ok "Flatpak flathub already configured"
  else
    quiet_run flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    ok "Flatpak flathub added"
  fi
}

flatpak_install_optional() {
  local ref="$1"
  pkg_present flatpak flatpak || { warn "flatpak not installed; skipping ${ref}"; return 0; }
  if flatpak info "$ref" >/dev/null 2>&1; then
    ok "Flatpak already installed: ${ref}"
    return 0
  fi
  quiet_run flatpak install -y --noninteractive flathub "$ref" \
    && ok "Flatpak installed: ${ref}" \
    || core_warn "Flatpak install failed: ${ref}"
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
  quiet_run run_as_real_user bash -c "
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
common_init_colors
theme_set_lane android
MISSING_PKGS=()
CORE_PKGS=(
  android-tools
  python3
  python3-pip
  wireshark
  flatpak
  curl
  unzip
)
while IFS= read -r pkg; do
  [[ -n "${pkg}" ]] && CORE_PKGS+=("${pkg}")
done < <(resolve_java_packages)
while IFS= read -r pkg; do
  [[ -n "${pkg}" ]] && CORE_PKGS+=("${pkg}")
done < <(resolve_node_packages)

android_core_status_render() {
  theme_report_header "Android core setup" "Android SDK, platform tools, Python tooling, and baseline packages"
  theme_section "Packages"
  android_check_version Java java -version
  if cmd_available adb; then
    theme_tool_row ok "adb" "$(adb version 2>&1 | head -n 1)"
  else
    theme_tool_row warn "adb" "not on PATH"
  fi
  if cmd_available node; then
    theme_tool_row ok "node" "$(node --version 2>&1 | head -n 1)"
  else
    theme_tool_row warn "node" "not on PATH"
  fi
  if cmd_available npm; then
    theme_tool_row ok "npm" "$(npm --version 2>&1 | head -n 1)"
  else
    theme_tool_row warn "npm" "not on PATH"
  fi
  echo
  theme_section "Android Studio"
  if cmd_available flatpak && flatpak info com.google.AndroidStudio >/dev/null 2>&1; then
    theme_status_ok "Android Studio flatpak installed"
  else
    theme_status_warn "Android Studio flatpak not installed"
  fi
  echo
  theme_section "Python tools"
  android_check_version Frida frida --version
  android_check_version Objection objection version
  android_check_version Mitmproxy mitmproxy --version
  if cmd_available drozer; then
    theme_tool_row ok "drozer" "$(drozer --version 2>&1 | head -n 1)"
  else
    theme_tool_row warn "drozer" "not on PATH"
  fi
  echo
  theme_section "SDK/PATH"
  if cmd_available sdkmanager; then
    theme_tool_row ok "sdkmanager" "$(sdkmanager --version 2>&1 | tail -n 1)"
  else
    theme_tool_row warn "sdkmanager" "not on PATH"
  fi
  if grep -qF '# >>> ANDROID SDK PATHS (managed) >>>' "${REAL_HOME}/.bashrc" 2>/dev/null; then
    theme_status_ok "Android SDK PATH block present in ~/.bashrc"
  else
    theme_status_warn "Android SDK PATH block missing from ~/.bashrc"
  fi
  theme_note "HOME sdk path: ${REAL_HOME}/Android/Sdk"
}

if (( STATUS_ONLY )); then
  android_core_status_render
  exit 0
fi

if (( QUIET_TERMINAL )); then
  theme_report_header "Android core setup" "Android SDK, platform tools, Python tooling, and baseline packages"
fi

ensure_user_bin_on_path

theme_section "Packages"
quiet_run pkg_install_batch_if_available MISSING_PKGS "${CORE_PKGS[@]}"
if ((${#MISSING_PKGS[@]} > 0)); then
  core_warn "Unavailable packages skipped: ${MISSING_PKGS[*]}"
else
  theme_status_ok "Baseline packages resolved"
fi
android_check_version Java java -version
if cmd_available adb; then
  theme_tool_row ok "adb" "$(adb version 2>&1 | head -n 1)"
else
  theme_tool_row warn "adb" "not on PATH"
fi
if cmd_available node; then
  theme_tool_row ok "node" "$(node --version 2>&1 | head -n 1)"
else
  theme_tool_row warn "node" "not on PATH"
fi
if cmd_available npm; then
  theme_tool_row ok "npm" "$(npm --version 2>&1 | head -n 1)"
else
  theme_tool_row warn "npm" "not on PATH"
fi
echo

theme_section "Android Studio"
flatpak_ensure_flathub
flatpak_install_optional com.google.AndroidStudio
if cmd_available flatpak && flatpak info com.google.AndroidStudio >/dev/null 2>&1; then
  theme_status_ok "Android Studio flatpak installed"
else
  theme_status_warn "Android Studio flatpak not installed"
fi
echo

theme_section "Python tools"
pip_user_upgrade_tools
pip_user_install frida-tools
pip_user_install objection
pip_user_install drozer || true
pip_user_install mitmproxy || true
android_check_version Frida frida --version
android_check_version Objection objection version
android_check_version Mitmproxy mitmproxy --version
if cmd_available drozer; then
  theme_tool_row ok "drozer" "$(drozer --version 2>&1 | head -n 1)"
else
  theme_tool_row warn "drozer" "not on PATH"
fi
echo

repair_node_tooling() {
  local node_pkg
  local node_pkgs=()

  theme_section "Repair Node/npm tooling"
  if ! cmd_available npm; then
    while IFS= read -r node_pkg; do
      [[ -n "${node_pkg}" ]] || continue
      node_pkgs+=("${node_pkg}")
    done < <(resolve_node_packages)
    if (( ${#node_pkgs[@]} > 0 )); then
      quiet_run pkg_install_batch_if_available MISSING_PKGS "${node_pkgs[@]}"
    fi
  fi
  if cmd_available npm; then
    if run_as_real_user_with_path npm -g list apk-mitm >/dev/null 2>&1; then
      ok "apk-mitm already installed globally"
    else
      quiet_run run_as_real_user_with_path npm install -g apk-mitm \
        && ok "apk-mitm installed globally" \
        || core_warn "apk-mitm install failed"
    fi
  else
    core_warn "npm command not found; skipped apk-mitm"
    info "NEXT run Repair Node/npm tooling or check npm package/PATH."
  fi
}

repair_node_tooling
if (( REPAIR_NODE_ONLY )); then
  theme_section "Status"
  if cmd_available npm; then
    theme_result_ready "Node/npm tooling repair complete"
  else
    theme_result_issues "Node/npm tooling still needs attention"
  fi
  exit 0
fi
echo

theme_section "SDK/PATH"
install_android_cmdline_tools
ensure_android_paths_in_bashrc
if cmd_available sdkmanager; then
  theme_tool_row ok "sdkmanager" "$(sdkmanager --version 2>&1 | tail -n 1)"
else
  theme_tool_row warn "sdkmanager" "not on PATH"
fi
if grep -qF '# >>> ANDROID SDK PATHS (managed) >>>' "${REAL_HOME}/.bashrc" 2>/dev/null; then
  theme_status_ok "Android SDK PATH block present in ~/.bashrc"
else
  theme_status_warn "Android SDK PATH block missing from ~/.bashrc"
fi
echo

theme_section "Warnings"
if ((${#CORE_WARNINGS[@]} == 0)); then
  theme_status_ok "No setup warnings"
else
  for _warn in "${CORE_WARNINGS[@]}"; do
    theme_status_warn "${_warn}"
  done
fi

echo
theme_section "Status"
if ((${#CORE_WARNINGS[@]} == 0)); then
  theme_result_ready "Android core setup complete"
else
  theme_result_issues "Android core setup completed with warnings"
fi
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
