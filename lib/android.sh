#!/usr/bin/env bash
# lib/android.sh — Android security / RE tool checks and diagnostics
# Version: 0.2.5
#
# Do not execute directly.

if [[ -n "${FEDORA_ANDROID_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_ANDROID_SH_LOADED=1

_AND_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_AND_LIB_DIR}/common.sh"
# shellcheck source=theme.sh
source "${_AND_LIB_DIR}/theme.sh"
# shellcheck source=host_context.sh
source "${_AND_LIB_DIR}/host_context.sh"

_android_theme_init() {
  common_init_colors
  theme_set_lane android
}

_android_verify_fail() {
  theme_tool_row err "$1" "${2:-}"
}

android_install_hint() {
  local tool="$1"
  case "${tool}" in
    apktool|jadx|smali|dex2jar)
      theme_note "Install: ./android/android_re_install.sh ${tool}"
      ;;
    "smali/baksmali")
      theme_note "Install: ./android/android_re_install.sh smali"
      ;;
    all)
      theme_note "Install all: ./android/android_re_install.sh all"
      theme_note "Menu: Android RE > RE tool installs > Install all + verify all"
      ;;
  esac
}

# Do not source ~/.bashrc (Fedora /etc/bashrc can trip nounset under set -u).
android_user_path_export() {
  export PATH="${HOME}/.local/bin:${PATH}"
}

# ---------- GitHub releases / user-scope downloads ----------
android_github_release_json() {
  local repo="$1"
  retry 3 3 curl -fsSL -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${repo}/releases/latest" \
    || die_with_hint "GitHub release lookup failed: ${repo}" \
      "Check network or GitHub rate limits; retry: ./android/android_re_install.sh <tool>"
}

android_github_pick_asset_url() {
  local json="$1"
  local pattern="$2"
  need_cmd python3
  python3 - "$json" "$pattern" <<'PY'
import json, re, sys
data = json.loads(sys.argv[1])
pat = re.compile(sys.argv[2])
for a in data.get("assets", []):
    name = a.get("name", "")
    url  = a.get("browser_download_url", "")
    if pat.search(name):
        print(url)
        sys.exit(0)
sys.exit(1)
PY
}

android_user_mktemp_dir() {
  run_as_real_user mktemp -d
}

android_user_download() {
  local url="$1"
  local dest="$2"
  run_as_real_user mkdir -p "$(dirname "$dest")"
  retry 3 2 run_as_real_user curl -L --fail -o "$dest" "$url" \
    || die_with_hint "Download failed: ${url}" \
      "Check network connectivity and disk space under $(real_home)"
}

# Run a verify function as the real user (explicit HOME + PATH for ~/.local/bin).
android_verify_as_user() {
  local fn="$1"
  local home userbin
  home="$(real_home)"
  userbin="${home}/.local/bin"
  run_as_real_user env "HOME=${home}" "PATH=${userbin}:${PATH}" \
    bash -c "source '${_AND_LIB_DIR}/android.sh' && ${fn}"
}

android_verify_script_usage() {
  local label="$1"
  local script="${2:-verify_${label}_install.sh}"
  cat <<EOF
Usage: ${script} [--help]

Verifies user-scope ${label} under ~/.local/ (install via android_re_*_user_install.sh).
EOF
}

# ---------- RE tool verification ----------
android_verify_apktool() {
  _android_theme_init
  android_user_path_export

  theme_verify_heading "apktool"
  if ! command -v apktool >/dev/null 2>&1; then
    _android_verify_fail "apktool" "not found on PATH"
    android_install_hint apktool
    return 2
  fi
  if ! apktool --version; then
    _android_verify_fail "apktool" "command exists but did not run cleanly"
    return 2
  fi

  theme_section "Paths"
  command -v apktool

  theme_section "JAR"
  local jar="${HOME}/.local/opt/apktool/apktool.jar"
  if [[ ! -f "${jar}" ]]; then
    _android_verify_fail "jar" "missing ${jar}"
    return 3
  fi
  ls -lh "${jar}"

  theme_status_ok "apktool verified"
}

android_verify_jadx() {
  _android_theme_init
  android_user_path_export

  theme_verify_heading "jadx"
  if ! command -v jadx >/dev/null 2>&1; then
    _android_verify_fail "jadx" "not found on PATH"
    android_install_hint jadx
    return 2
  fi
  if ! jadx --version; then
    _android_verify_fail "jadx" "command exists but did not run cleanly"
    return 2
  fi

  theme_section "jadx-gui"
  if ! command -v jadx-gui >/dev/null 2>&1; then
    _android_verify_fail "jadx-gui" "not found on PATH"
    android_install_hint jadx
    return 2
  fi
  if ! jadx-gui --version; then
    _android_verify_fail "jadx-gui" "command exists but did not run cleanly"
    return 2
  fi

  theme_section "Paths"
  command -v jadx jadx-gui

  theme_section "Install dir"
  if [[ -d "${HOME}/.local/opt/jadx" ]]; then
    theme_status_ok "${HOME}/.local/opt/jadx exists"
  else
    _android_verify_fail "opt dir" "missing"
    return 3
  fi

  theme_section "JAR presence"
  ls -lh "${HOME}/.local/opt/jadx/lib/"*.jar 2>/dev/null | head || theme_status_warn "no jars under lib/"

  theme_status_ok "jadx verified"
}

android_verify_smali() {
  _android_theme_init
  android_user_path_export

  theme_verify_heading "smali / baksmali"
  if ! command -v smali >/dev/null 2>&1; then
    _android_verify_fail "smali" "not found on PATH"
    android_install_hint "smali/baksmali"
    return 2
  fi
  if ! smali --version; then
    _android_verify_fail "smali" "command exists but did not run cleanly"
    return 2
  fi

  theme_section "baksmali"
  if ! command -v baksmali >/dev/null 2>&1; then
    _android_verify_fail "baksmali" "not found on PATH"
    android_install_hint "smali/baksmali"
    return 2
  fi
  if ! baksmali --version; then
    _android_verify_fail "baksmali" "command exists but did not run cleanly"
    return 2
  fi

  theme_section "Paths"
  command -v smali baksmali

  theme_section "JARs"
  shopt -s nullglob
  local jars=( "${HOME}/.local/opt/smali/"*.jar )
  shopt -u nullglob
  if ((${#jars[@]} == 0)); then
    _android_verify_fail "jars" "none under ${HOME}/.local/opt/smali/"
    return 3
  fi
  ls -lh "${jars[@]}"

  theme_status_ok "smali/baksmali verified"
}

android_verify_dex2jar() {
  _android_theme_init
  android_user_path_export

  theme_verify_heading "dex2jar (d2j tools)"
  local tool found=0
  for tool in d2j-dex2jar d2j-jar2dex d2j-apk-sign; do
    if command -v "${tool}" >/dev/null 2>&1; then
      theme_status_ok "${tool}: $(command -v "${tool}")"
      found=$((found + 1))
    else
      _android_verify_fail "${tool}" "not found on PATH"
    fi
  done

  theme_section "Install dir"
  if [[ -d "${HOME}/.local/opt/dex2jar/current" ]]; then
    theme_status_ok "${HOME}/.local/opt/dex2jar/current exists"
  else
    _android_verify_fail "dex2jar" "install dir missing"
    android_install_hint dex2jar
    return 3
  fi

  if (( found == 0 )); then
    return 2
  fi
  if (( found < 3 )); then
    return 2
  fi

  if command -v d2j-dex2jar >/dev/null 2>&1 && d2j-dex2jar -h >/dev/null 2>&1; then
    theme_status_ok "d2j-dex2jar runnable"
  elif command -v d2j-dex2jar.sh >/dev/null 2>&1 && d2j-dex2jar.sh -h >/dev/null 2>&1; then
    theme_status_ok "d2j-dex2jar.sh runnable"
  else
    theme_status_warn "d2j-dex2jar present but did not run cleanly"
  fi

  theme_section "Linked tools"
  local f found=0 count=0 max_show=8
  shopt -s nullglob
  for f in "${HOME}/.local/bin"/d2j-*; do
    [[ "${f}" == *.bat ]] && continue
    count=$((count + 1))
    if (( count <= max_show )); then
      theme_note "${f}"
      found=1
    fi
  done
  shopt -u nullglob
  if (( count > max_show )); then
    theme_note "... and $(( count - max_show )) more d2j-* tools in ~/.local/bin"
    found=1
  fi
  (( found )) || theme_note "(none)"

  theme_status_ok "dex2jar verified"
}

android_verify_all_re_tools() {
  _android_theme_init
  local rc=0
  local -a names=(apktool jadx "smali/baksmali" dex2jar)
  local -a fns=(android_verify_apktool android_verify_jadx android_verify_smali android_verify_dex2jar)
  local i name fn

  for i in "${!names[@]}"; do
    name="${names[$i]}"
    fn="${fns[$i]}"
    theme_report_section "Verify: ${name}"
    if ! "${fn}"; then
      rc=1
    fi
    echo
  done

  if (( rc == 0 )); then
    theme_result_ready "All Android RE tools verified"
  else
    theme_result_issues "One or more Android RE tools failed verification"
    android_install_hint all
  fi
  return "${rc}"
}

# ---------- ADB / core tooling ----------
android_check_version() {
  local label="$1"
  shift
  local bin="$1"

  if ! cmd_available "${bin}"; then
    theme_tool_row miss "${label}" "not installed"
    return 0
  fi

  local raw line=""
  raw="$("$@" 2>&1)" || true
  if [[ -z "${raw}" ]]; then
    theme_tool_row warn "${label}" "no version output"
    return 0
  fi
  if grep -qiE 'traceback \(most recent|modulenotfounderror|importerror|no such option' <<< "${raw}"; then
    line="$(printf '%s\n' "${raw}" | sed -n '/./p' | grep -iE 'modulenotfounderror|importerror|no such option' | head -n 1 || true)"
    [[ -n "${line}" ]] || line="$(printf '%s\n' "${raw}" | sed -n '/./p' | tail -n 1)"
    theme_tool_row warn "${label}" "broken (${line})"
    if [[ "${label}" == "Mitmproxy" ]]; then
      theme_note "pip3 install --upgrade --force-reinstall mitmproxy"
    fi
    return 0
  fi
  line="$(printf '%s\n' "${raw}" | sed -n '/./p' | tail -n 1)"
  if [[ -n "${line}" ]]; then
    theme_tool_row ok "${label}" "${line}"
  else
    theme_tool_row warn "${label}" "no version output"
  fi
}

android_core_tool_status() {
  local rc=0
  if ! cmd_available java; then
    warn "Java not on PATH (install OpenJDK or run android_dev_core_setup.sh)"
    rc=1
  fi
  android_check_version Java java -version
  android_check_version Python3 python3 --version
  android_check_version Frida frida --version
  android_check_version Objection objection version
  android_check_version Mitmproxy mitmproxy --version
  if ! cmd_available sdkmanager; then
    warn "sdkmanager not on PATH (run android_dev_core_setup.sh)"
    rc=1
  else
    android_check_version sdkmanager sdkmanager --version
  fi
  return "${rc}"
}

android_adb_status() {
  local mode="${1:-full}"
  _android_theme_init

  theme_verify_heading "ADB"
  if ! cmd_available adb; then
    _android_verify_fail "adb" "not found on PATH"
    theme_note "Install android-tools (dnf) or run android_dev_core_setup.sh"
    return 2
  fi

  theme_kv "Path" "$(cmd_binary_path adb)"
  adb version 2>&1 | head -n 2

  if [[ "${mode}" == "full" ]]; then
    echo
    theme_section "Connected devices"
    adb devices -l
  else
    echo
    theme_section "Connected devices"
    theme_note "Skipped in doctor mode to avoid starting the ADB daemon."
    theme_note "Use Android menu > Doctors & ADB > ADB to enumerate devices."
  fi

  echo
  theme_section "USB / udev hints"
  if [[ -d /etc/udev/rules.d ]]; then
    local rules
    rules="$(grep -l 'android\|adb' /etc/udev/rules.d/*.rules 2>/dev/null | head -n 3 || true)"
    if [[ -n "${rules}" ]]; then
      theme_status_ok "Found udev rules"
      printf '%s\n' ${rules} | sed 's/^/    /'
    else
      theme_status_warn "No obvious Android udev rules in /etc/udev/rules.d/"
      theme_note "Fedora usually ships android-tools; replug device after setup."
    fi
  fi
}

doctor_android_research() {
  local rc=0

  common_init_colors
  theme_set_lane android
  theme_report_header "Android Research Workstation Doctor" \
    "Host: $(hostname) · User: $(real_user)"
  if [[ "${FEDORA_SKIP_RUNTIME_AWARENESS:-0}" != 1 ]]; then
    health_print_runtime_awareness
    echo
    host_context_remediation_notes
    echo
  fi

  theme_section "Core tooling"
  android_core_tool_status || rc=1
  echo

  android_adb_status brief || rc=1
  echo

  theme_section "Reverse-engineering tools"
  android_verify_all_re_tools || rc=1

  echo
  theme_rule '─'
  if (( rc == 0 )); then
    theme_result_ready "Result: READY (all checks passed)"
  else
    theme_result_issues "Result: ISSUES FOUND (review output above)"
  fi
  theme_rule '─'
  return "${rc}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
