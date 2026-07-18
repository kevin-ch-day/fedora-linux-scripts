#!/usr/bin/env bash
# android_dev_core_setup.sh
# Android dev + security core setup (Fedora)
# Version: 0.7.1
#
# Stable installs only:
# - dnf: available OpenJDK + Node.js packages, adb/fastboot, python3/pip, wireshark, flatpak, unzip/curl
# - flatpak: Android Studio (optional)
# - pip (user): frida-tools, objection, drozer, mitmproxy
# - Android SDK cmdline-tools + PATH
#
# Run: sudo ./android_dev_core_setup.sh [--preset minimal|standard|full]
#      ./android_dev_core_setup.sh --status
#      ./android_dev_core_setup.sh --preset minimal --plan
#      ./android_dev_core_setup.sh --repair-shell
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
Usage: $(basename "$0") [options]

Flexible Android dev + security setup for $(real_user).

Presets:
  minimal    Headless/device host: Java · adb/fastboot · SDK command-line tools
  standard   Recommended RE workstation: minimal + Python tools · Wireshark · Android Studio
  full       Standard + Node/npm · apk-mitm

Modes:
  --status                 Read-only status for all capabilities
  --plan                   Show resolved components; change nothing
  --repair-shell           Repair only the managed SDK block in ~/.bashrc (no sudo)
  --repair-node            Repair Node/npm + apk-mitm only

Component overrides:
  --with-studio | --without-studio
  --with-python | --without-python
  --with-node | --without-node
  --with-wireshark | --without-wireshark
  --with-sdk | --without-sdk
  --with-shell-rc | --without-shell-rc

Paths and versions:
  --sdk-root DIR           User-owned SDK location (default: ~/Android/Sdk)
  --cmdline-tools-version N
                            Pinned Google command-line tools build

Other:
  --preset NAME            minimal | standard | full (default: standard)
  --help, -h               Show this help

Logs to: logs/android_dev_core.log

Install and --repair-node require sudo. --status, --plan, and --repair-shell do not.
EOF
}

ANDROID_CORE_PRESET="standard"
STATUS_ONLY=0
PLAN_ONLY=0
REPAIR_SHELL_ONLY=0
REPAIR_NODE_ONLY=0
QUIET_TERMINAL=0
WITH_STUDIO=1
WITH_PYTHON=1
WITH_NODE=0
WITH_WIRESHARK=1
WITH_SDK=1
WITH_SHELL_RC=1
SDK_ROOT_ARG=""
CMDLINE_TOOLS_VERSION="${ANDROID_CMDLINE_TOOLS_VERSION:-14742923}"
declare -a CORE_WARNINGS=()

_core_apply_preset() {
  case "$1" in
    minimal)
      WITH_STUDIO=0
      WITH_PYTHON=0
      WITH_NODE=0
      WITH_WIRESHARK=0
      WITH_SDK=1
      WITH_SHELL_RC=1
      ;;
    standard)
      WITH_STUDIO=1
      WITH_PYTHON=1
      WITH_NODE=0
      WITH_WIRESHARK=1
      WITH_SDK=1
      WITH_SHELL_RC=1
      ;;
    full)
      WITH_STUDIO=1
      WITH_PYTHON=1
      WITH_NODE=1
      WITH_WIRESHARK=1
      WITH_SDK=1
      WITH_SHELL_RC=1
      ;;
    *) die "Unknown Android preset: $1 (use minimal, standard, or full)" ;;
  esac
}

# Resolve the preset before component overrides so argument order is
# unsurprising: explicit --with/--without flags always win.
_core_args=("$@")
for ((_core_i = 0; _core_i < ${#_core_args[@]}; _core_i++)); do
  if [[ "${_core_args[$_core_i]}" == "--preset" ]]; then
    ((_core_i + 1 < ${#_core_args[@]})) || die "--preset requires a name"
    ANDROID_CORE_PRESET="${_core_args[$((_core_i + 1))]}"
  fi
done
_core_apply_preset "${ANDROID_CORE_PRESET}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --preset)
      shift
      [[ $# -gt 0 ]] || die "--preset requires a name"
      # Already resolved above; consume the value.
      shift
      ;;
    --status) STATUS_ONLY=1; shift ;;
    --plan) PLAN_ONLY=1; shift ;;
    --repair-shell) REPAIR_SHELL_ONLY=1; shift ;;
    --repair-node) REPAIR_NODE_ONLY=1; WITH_NODE=1; shift ;;
    --with-studio) WITH_STUDIO=1; shift ;;
    --without-studio) WITH_STUDIO=0; shift ;;
    --with-python) WITH_PYTHON=1; shift ;;
    --without-python) WITH_PYTHON=0; shift ;;
    --with-node) WITH_NODE=1; shift ;;
    --without-node) WITH_NODE=0; shift ;;
    --with-wireshark) WITH_WIRESHARK=1; shift ;;
    --without-wireshark) WITH_WIRESHARK=0; shift ;;
    --with-sdk) WITH_SDK=1; shift ;;
    --without-sdk) WITH_SDK=0; WITH_SHELL_RC=0; shift ;;
    --with-shell-rc) WITH_SHELL_RC=1; shift ;;
    --without-shell-rc) WITH_SHELL_RC=0; shift ;;
    --sdk-root)
      shift
      [[ $# -gt 0 ]] || die "--sdk-root requires a directory"
      SDK_ROOT_ARG="$1"
      shift
      ;;
    --cmdline-tools-version)
      shift
      [[ $# -gt 0 ]] || die "--cmdline-tools-version requires a build number"
      CMDLINE_TOOLS_VERSION="$1"
      shift
      ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

(( REPAIR_NODE_ONLY )) && WITH_NODE=1
(( STATUS_ONLY + PLAN_ONLY + REPAIR_SHELL_ONLY + REPAIR_NODE_ONLY <= 1 )) ||
  die "--status, --plan, --repair-shell, and --repair-node are separate modes"
[[ "${CMDLINE_TOOLS_VERSION}" =~ ^[0-9]+$ ]] ||
  die "--cmdline-tools-version must be numeric"

REAL_HOME="$(real_home)"
if [[ -n "${SDK_ROOT_ARG}" ]]; then
  [[ "${SDK_ROOT_ARG}" == /* ]] || die "--sdk-root must be an absolute path"
  ANDROID_SDK_DIR="${SDK_ROOT_ARG%/}"
else
  ANDROID_SDK_DIR="${REAL_HOME}/Android/Sdk"
fi
case "${ANDROID_SDK_DIR}" in
  "${REAL_HOME}"|"${REAL_HOME}"/*) ;;
  *) die "--sdk-root must be inside ${REAL_HOME} for this user-scoped installer" ;;
esac

if [[ "${FEDORA_ANDROID_MENU_MODE:-0}" == 1 && "${FEDORA_VERBOSE:-0}" != 1 ]]; then
  QUIET_TERMINAL=1
  export FEDORA_LOG_TERMINAL_BANNER=0
  export FEDORA_LOG_TERMINAL_FOOTER=0
  export FEDORA_LOG_TERMINAL_STRUCTURED=0
fi

android_core_user_path() {
  local userbin="${REAL_HOME}/.local/bin"
  printf '%s:%s/cmdline-tools/latest/bin:%s/platform-tools:%s' \
    "${userbin}" "${ANDROID_SDK_DIR}" "${ANDROID_SDK_DIR}" "${PATH}"
}

run_as_real_user_with_path() {
  run_as_real_user env "HOME=${REAL_HOME}" "PATH=$(android_core_user_path)" "$@"
}

user_has_cmd() {
  local cmd="$1"
  run_as_real_user_with_path bash -lc "command -v $(printf '%q' "$cmd")" >/dev/null 2>&1
}

core_row_cmd() {
  local label="$1" cmd="$2"
  shift 2
  local -a version_args=("$@")
  local detail="not on PATH"

  if user_has_cmd "${cmd}"; then
    if ((${#version_args[@]} > 0)); then
      detail="$(run_as_real_user_with_path bash -lc \
        "$(printf '%q' "$cmd") $(printf '%q ' "${version_args[@]}")" 2>&1 | head -n 1)"
    else
      detail="on PATH"
    fi
    theme_tool_row ok "${label}" "${detail}"
    return 0
  fi
  if cmd_available "${cmd}"; then
    if ((${#version_args[@]} > 0)); then
      detail="$("${cmd}" "${version_args[@]}" 2>&1 | head -n 1)"
    else
      detail="on system PATH only"
    fi
    theme_status_info "${label}: ${detail} (reload shell: source ~/.bashrc)"
    return 0
  fi
  theme_tool_row warn "${label}" "${detail}"
  return 1
}

core_row_optional_node_tool() {
  local label="$1" cmd="$2"
  local detail="optional (required for apk-mitm only); not on PATH"
  local version_flag="--version"

  if user_has_cmd "${cmd}"; then
    detail="$(run_as_real_user_with_path bash -lc \
      "$(printf '%q' "$cmd") ${version_flag}" 2>&1 | head -n 1)"
    theme_tool_row ok "${label}" "${detail}"
    return 0
  fi
  if cmd_available "${cmd}"; then
    detail="$("${cmd}" "${version_flag}" 2>&1 | head -n 1) (system PATH only)"
    theme_status_info "${label}: ${detail}"
    return 0
  fi
  theme_status_info "${label}: ${detail}"
  return 1
}

core_version_line_from_output() {
  local raw="$1"
  local line=""

  if grep -qiE 'unknown command|traceback \(most recent|modulenotfounderror|importerror|no such option' <<< "${raw}"; then
    return 1
  fi
  line="$(printf '%s\n' "${raw}" | grep -E '^[0-9]+(\.[0-9]+)*$' | tail -n 1)"
  if [[ -z "${line}" ]]; then
    line="$(printf '%s\n' "${raw}" | sed -n '/./p' | grep -viE '^Warning:' | tail -n 1)"
  fi
  [[ -n "${line}" ]] || return 1
  printf '%s\n' "${line}"
}

core_row_drozer() {
  if user_has_cmd drozer; then
    theme_tool_row ok "drozer" "installed"
    return 0
  fi
  if cmd_available drozer; then
    theme_status_info "drozer: installed (reload shell: source ~/.bashrc)"
    return 0
  fi
  theme_tool_row warn "drozer" "not on PATH"
  return 1
}

core_sdkmanager_version() {
  local raw=""

  if user_has_cmd sdkmanager; then
    raw="$(run_as_real_user_with_path bash -lc 'sdkmanager --version' 2>&1)" || true
  elif cmd_available sdkmanager; then
    raw="$(sdkmanager --version 2>&1)" || true
  else
    return 1
  fi
  core_version_line_from_output "${raw}" || printf '%s\n' "installed"
}

core_row_sdkmanager() {
  local detail=""

  if user_has_cmd sdkmanager; then
    detail="$(core_sdkmanager_version)"
    theme_tool_row ok "sdkmanager" "${detail}"
    return 0
  fi
  if cmd_available sdkmanager; then
    detail="$(core_sdkmanager_version)"
    theme_status_info "sdkmanager: ${detail} (reload shell: source ~/.bashrc)"
    return 0
  fi
  theme_tool_row warn "sdkmanager" "not on PATH"
  return 1
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
  if flatpak remotes --columns=name 2>/dev/null | grep -qx flathub; then
    ok "Flatpak flathub already configured"
    return 0
  fi
  if flatpak remotes --show-disabled --columns=name 2>/dev/null | grep -qx flathub; then
    if quiet_run flatpak remote-modify --enable flathub; then
      ok "Flatpak flathub enabled"
      return 0
    fi
    core_warn "Flathub exists but could not be enabled"
    return 1
  fi
  if quiet_run flatpak remote-add --if-not-exists \
    flathub https://flathub.org/repo/flathub.flatpakrepo; then
    ok "Flatpak flathub added"
    return 0
  fi
  core_warn "Flathub could not be added"
  return 1
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
  local sdk_dir="${ANDROID_SDK_DIR}"
  local tools_dir="${sdk_dir}/cmdline-tools"
  local latest_dir="${tools_dir}/latest"
  local archive_url="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip"

  run_as_real_user mkdir -p "${tools_dir}"
  if [[ -d "${latest_dir}" ]] && [[ -x "${latest_dir}/bin/sdkmanager" ]]; then
    ok "Android SDK cmdline-tools already present"
    return 0
  fi

  info "Installing Android SDK command-line tools into: ${latest_dir}"
  quiet_run run_as_real_user bash -c '
set -euo pipefail
latest_dir="$1"
archive_url="$2"
tmp=$(mktemp -d)
trap '"'"'rm -rf "${tmp}"'"'"' EXIT
zip="${tmp}/cmdline-tools.zip"
curl -L --fail --retry 3 --retry-delay 2 -o "${zip}" \
  "${archive_url}"
mkdir -p "${tmp}/extract"
unzip -q "${zip}" -d "${tmp}/extract"
rm -rf "${latest_dir}"
mkdir -p "${latest_dir}"
mv "${tmp}/extract/cmdline-tools/"* "${latest_dir}/"
' _ "${latest_dir}" "${archive_url}"
  chown -R "$(real_user):$(real_user)" "${sdk_dir}" 2>/dev/null || true
  ok "Android SDK cmdline-tools ${CMDLINE_TOOLS_VERSION} installed"
}

android_sdk_managed_block_body() {
  local shell_sdk_path
  if [[ "${ANDROID_SDK_DIR}" == "${REAL_HOME}" ]]; then
    shell_sdk_path='$HOME'
  else
    shell_sdk_path="\$HOME/${ANDROID_SDK_DIR#"${REAL_HOME}/"}"
  fi
  cat <<EOF
# >>> ANDROID SDK PATHS (managed) >>>
export ANDROID_HOME="${shell_sdk_path}"
case ":\$PATH:" in
  *":\$ANDROID_HOME/cmdline-tools/latest/bin:"*) ;;
  *) export PATH="\$PATH:\$ANDROID_HOME/cmdline-tools/latest/bin" ;;
esac
case ":\$PATH:" in
  *":\$ANDROID_HOME/platform-tools:"*) ;;
  *) export PATH="\$PATH:\$ANDROID_HOME/platform-tools" ;;
esac
# <<< ANDROID SDK PATHS (managed) <<<
EOF
}

bashrc_has_legacy_android_path_block() {
  local bashrc="$1"
  [[ -f "${bashrc}" ]] || return 1
  grep -qF 'export ANDROID_HOME="$HOME/Android/Sdk"' "${bashrc}" 2>/dev/null \
    && ! grep -qF '# >>> ANDROID SDK PATHS (managed) >>>' "${bashrc}" 2>/dev/null
}

bashrc_android_path_status() {
  local bashrc="${REAL_HOME}/.bashrc"
  if grep -qF '# >>> ANDROID SDK PATHS (managed) >>>' "${bashrc}" 2>/dev/null; then
    theme_status_ok "Android SDK PATH block present in ~/.bashrc (managed)"
  elif bashrc_has_legacy_android_path_block "${bashrc}"; then
    theme_status_warn "Legacy unmarked Android SDK PATH block in ~/.bashrc"
    theme_status_info "Run setup (install mode) to migrate; --status does not modify ~/.bashrc"
  else
    theme_status_warn "Android SDK PATH block missing from ~/.bashrc"
    theme_status_info "Repair only this block: ./android/android_dev_core_setup.sh --repair-shell"
  fi
}

_write_bashrc_android_sdk_paths() {
  local bashrc="${REAL_HOME}/.bashrc"
  local marker_begin="# >>> ANDROID SDK PATHS (managed) >>>"
  local marker_end="# <<< ANDROID SDK PATHS (managed) <<<"
  local tmp_dir tmp block_file owner_group
  # Build under an effective-user-owned directory. Fedora's protected_regular
  # policy can reject root redirects to files created by the invoking user in
  # /tmp, even though the final ~/.bashrc copy correctly runs as that user.
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/fedora-android-shell.XXXXXX")"
  tmp="${tmp_dir}/bashrc"
  block_file="${tmp_dir}/android-path-block"
  touch "${tmp}" "${block_file}"
  chmod 0600 "${tmp}" "${block_file}"
  android_sdk_managed_block_body > "${block_file}"

  run_as_real_user touch "${bashrc}"
  if grep -qF "${marker_begin}" "${bashrc}" 2>/dev/null; then
    info "Rewriting Android SDK PATH managed block in ${bashrc}"
    awk -v begin="${marker_begin}" -v end="${marker_end}" -v blockfile="${block_file}" '
      BEGIN { while ((getline line < blockfile) > 0) block = block line "\n" }
      $0 == begin { printf "%s", block; skip = 1; next }
      skip && $0 == end { skip = 0; next }
      skip { next }
      { print }
    ' "${bashrc}" > "${tmp}"
  elif bashrc_has_legacy_android_path_block "${bashrc}"; then
    info "Migrating legacy Android SDK PATH block to managed block in ${bashrc}"
    awk '
      /^export ANDROID_HOME="\$HOME\/Android\/Sdk"$/ { leg = 1; next }
      leg == 1 && /^export ANDROID_SDK_ROOT=/ { leg = 2; next }
      leg == 2 && /cmdline-tools\/latest\/bin/ && /platform-tools/ { leg = 0; next }
      { print }
    ' "${bashrc}" > "${tmp}"
    printf '\n' >> "${tmp}"
    cat "${block_file}" >> "${tmp}"
  else
    info "Adding Android SDK PATH block to ${bashrc}"
    cat "${bashrc}" > "${tmp}"
    printf '\n' >> "${tmp}"
    cat "${block_file}" >> "${tmp}"
  fi

  owner_group="$(id -gn "$(real_user)")"
  if [[ "${EUID}" -eq 0 ]]; then
    chown -R "$(real_user):${owner_group}" "${tmp_dir}"
  fi
  run_as_real_user cp "${tmp}" "${bashrc}"
  chown "$(id -u "$(real_user)"):$(id -g "$(real_user)")" "${bashrc}" 2>/dev/null || true
  rm -rf "${tmp_dir}"
}

ensure_android_paths_in_bashrc() {
  _write_bashrc_android_sdk_paths
  ok "Android SDK PATH block ensured in ${REAL_HOME}/.bashrc"
}

repair_node_tooling() {
  local node_pkg
  local node_pkgs=()

  theme_section "Repair Node/npm tooling"
  if ! cmd_available npm; then
    while IFS= read -r node_pkg; do
      [[ -n "${node_pkg}" ]] || continue
      node_pkgs+=("${node_pkg}")
    done < <(resolve_node_packages)
    if ((${#node_pkgs[@]} > 0)); then
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
    info "Node/npm optional (required for apk-mitm only); skipped apk-mitm"
    info "NEXT: retry with: sudo -E ./android/android_dev_core_setup.sh --repair-node"
  fi
}

android_core_status_render() {
  local rc=0

  theme_lane_banner "Android core status" android \
    "MODE / read-only · USER / $(real_user) · target-user PATH"
  echo
  theme_section "Packages"
  core_row_cmd Java java -version || rc=1
  core_row_cmd adb adb version || rc=1
  core_row_optional_node_tool node node || true
  core_row_optional_node_tool npm npm || true
  echo
  theme_section "Android Studio"
  if cmd_available flatpak && flatpak info com.google.AndroidStudio >/dev/null 2>&1; then
    theme_status_ok "Android Studio flatpak installed"
  else
    theme_status_warn "Android Studio flatpak not installed"
  fi
  echo
  theme_section "Python tools"
  core_row_cmd Frida frida --version || rc=1
  core_row_cmd Objection objection version || rc=1
  core_row_cmd Mitmproxy mitmproxy --version || rc=1
  core_row_drozer || rc=1
  echo
  theme_section "SDK/PATH"
  core_row_sdkmanager || rc=1
  bashrc_android_path_status
  theme_note "SDK path: ${ANDROID_SDK_DIR}"
  return "${rc}"
}

android_core_plan_render() {
  common_init_colors
  theme_set_lane android
  theme_lane_banner "Android core install plan" android \
    "PRESET / ${ANDROID_CORE_PRESET} · USER / $(real_user) · MODE / no changes"
  theme_kv "SDK root" "${ANDROID_SDK_DIR}"
  theme_kv "CLI tools build" "${CMDLINE_TOOLS_VERSION}"
  echo
  theme_section "Resolved capabilities"
  theme_tool_row ok "Base" "Java · adb/fastboot"
  if (( WITH_SDK )); then
    theme_tool_row ok "SDK CLI" "command-line tools → ${ANDROID_SDK_DIR}"
  else
    theme_tool_row skip "SDK CLI" "disabled"
  fi
  if (( WITH_PYTHON )); then
    theme_tool_row ok "Python RE" "frida · objection · drozer · mitmproxy"
  else
    theme_tool_row skip "Python RE" "disabled"
  fi
  if (( WITH_STUDIO )); then
    theme_tool_row ok "Android Studio" "Flatpak / Flathub"
  else
    theme_tool_row skip "Android Studio" "disabled"
  fi
  if (( WITH_WIRESHARK )); then
    theme_tool_row ok "Wireshark" "Fedora package"
  else
    theme_tool_row skip "Wireshark" "disabled"
  fi
  if (( WITH_NODE )); then
    theme_tool_row ok "Node tooling" "node · npm · apk-mitm"
  else
    theme_tool_row skip "Node tooling" "disabled (optional)"
  fi
  if (( WITH_SDK && WITH_SHELL_RC )); then
    theme_tool_row ok "Shell PATH" "managed ~/.bashrc block"
  else
    theme_tool_row skip "Shell PATH" "no shell file changes"
  fi
  echo
  theme_note "Install: sudo -E ./android/android_dev_core_setup.sh --preset ${ANDROID_CORE_PRESET}"
  theme_note "Adjust: add --without-studio, --without-python, --without-shell-rc, or another override"
}

if [[ "${FEDORA_ANDROID_CORE_LIB_ONLY:-0}" == 1 ]]; then
  return 0 2>/dev/null || exit 0
fi

if (( STATUS_ONLY )); then
  status_rc=0
  common_init_colors
  theme_set_lane android
  android_core_status_render || status_rc=$?
  exit "${status_rc}"
fi

if (( PLAN_ONLY )); then
  android_core_plan_render
  exit 0
fi

if (( REPAIR_SHELL_ONLY )); then
  common_init_colors
  theme_set_lane android
  theme_lane_banner "Android SDK shell repair" android \
    "SCOPE / ~/.bashrc managed block only · USER / $(real_user)"
  if [[ ! -x "${ANDROID_SDK_DIR}/cmdline-tools/latest/bin/sdkmanager" ]]; then
    die "SDK command-line tools not found under ${ANDROID_SDK_DIR}; run --status first"
  fi
  ensure_android_paths_in_bashrc
  bashrc_android_path_status
  theme_result_ready "Shell PATH repair complete · run: source ~/.bashrc"
  exit 0
fi

# ---------- Main ----------
require_root
init_script_logging "${FEDORA_LOG_ANDROID_CORE}" "android_dev_core_setup.sh" "Android dev core setup"
common_init_colors
theme_set_lane android
MISSING_PKGS=()

if (( REPAIR_NODE_ONLY )); then
  theme_report_header "Android Node tooling repair" "node · npm · apk-mitm only"
  repair_node_tooling
  echo
  theme_section "Status"
  if cmd_available npm; then
    theme_result_ready "Node/npm tooling repair complete"
  else
    theme_result_issues "Node/npm tooling still needs attention"
  fi
  exit 0
fi

CORE_PKGS=(
  android-tools
)
if (( WITH_SDK )); then
  CORE_PKGS+=(curl unzip)
fi
if (( WITH_PYTHON )); then
  CORE_PKGS+=(python3 python3-pip)
fi
if (( WITH_WIRESHARK )); then
  CORE_PKGS+=(wireshark)
fi
if (( WITH_STUDIO )); then
  CORE_PKGS+=(flatpak)
fi
while IFS= read -r pkg; do
  [[ -n "${pkg}" ]] && CORE_PKGS+=("${pkg}")
done < <(resolve_java_packages)
while IFS= read -r pkg; do
  [[ -n "${pkg}" ]] && CORE_PKGS+=("${pkg}")
done < <(
  if (( WITH_NODE )); then
    resolve_node_packages
  fi
)

if (( QUIET_TERMINAL )); then
  theme_lane_banner "Android core setup" android \
    "PRESET / ${ANDROID_CORE_PRESET} · flexible workstation capabilities"
fi

ensure_user_bin_on_path
theme_status_info "Post-install checks use $(real_user) PATH (~/.local/bin + Android SDK). Reload shell when done: source ~/.bashrc"
echo

theme_section "Packages"
quiet_run pkg_install_batch_if_available MISSING_PKGS "${CORE_PKGS[@]}"
if ((${#MISSING_PKGS[@]} > 0)); then
  core_warn "Unavailable packages skipped: ${MISSING_PKGS[*]}"
else
  theme_status_ok "Baseline packages resolved"
fi
core_row_cmd Java java -version || core_warn "Java is not available after package setup"
core_row_cmd adb adb version || core_warn "adb is not available after package setup"
core_row_optional_node_tool node node || true
core_row_optional_node_tool npm npm || true
echo

theme_section "Android Studio"
if (( WITH_STUDIO )); then
  if flatpak_ensure_flathub; then
    flatpak_install_optional com.google.AndroidStudio
  fi
  if cmd_available flatpak && flatpak info com.google.AndroidStudio >/dev/null 2>&1; then
    theme_status_ok "Android Studio flatpak installed"
  else
    theme_status_warn "Android Studio flatpak not installed"
  fi
else
  theme_status_info "Skipped by preset/override"
fi
echo

theme_section "Python tools"
if (( WITH_PYTHON )); then
  pip_user_upgrade_tools
  pip_user_install frida-tools
  pip_user_install objection
  pip_user_install drozer || true
  pip_user_install mitmproxy || true
  core_row_cmd Frida frida --version || core_warn "Frida is not available after pip setup"
  core_row_cmd Objection objection version || core_warn "Objection is not available after pip setup"
  core_row_cmd Mitmproxy mitmproxy --version || core_warn "Mitmproxy is not available after pip setup"
  core_row_drozer || core_warn "drozer is not available after pip setup"
else
  theme_status_info "Skipped by preset/override"
fi
echo

if (( WITH_NODE )); then
  repair_node_tooling
else
  theme_section "Node/npm tooling"
  theme_status_info "Skipped (optional; use --with-node or the full preset for apk-mitm)"
fi
echo

theme_section "SDK/PATH"
if (( WITH_SDK )); then
  install_android_cmdline_tools
  if (( WITH_SHELL_RC )); then
    ensure_android_paths_in_bashrc
  else
    theme_status_info "Shell PATH changes skipped; export ANDROID_HOME=${ANDROID_SDK_DIR} manually"
  fi
  core_row_sdkmanager || core_warn "sdkmanager is not available after SDK setup"
  (( WITH_SHELL_RC )) && bashrc_android_path_status
else
  theme_status_info "SDK command-line tools skipped by preset/override"
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
if (( WITH_SDK && WITH_SHELL_RC )); then
  theme_note "Reload shell: source ~/.bashrc"
else
  theme_note "No shell reload required by this run"
fi
echo

if ((${#MISSING_PKGS[@]} > 0)); then
  warn "Packages not available in enabled repos:"
  printf '  - %s\n' "${MISSING_PKGS[@]}"
  echo
fi

theme_note "APK tools: ./android/android_re_install.sh all"
theme_note "Consolidated status: ./android/android_dev_core_setup.sh --status"
