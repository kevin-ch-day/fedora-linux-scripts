#!/usr/bin/env bash
# lib/android.sh — Android security / RE tool checks and diagnostics
# Version: 0.2.4
#
# Do not execute directly.

if [[ -n "${FEDORA_ANDROID_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_ANDROID_SH_LOADED=1

_AND_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_AND_LIB_DIR}/common.sh"

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
  android_user_path_export

  echo "== apktool =="
  command -v apktool >/dev/null 2>&1 || { echo "[ERROR] apktool not found on PATH"; return 2; }
  apktool --version

  echo "== paths =="
  command -v apktool

  echo "== jar =="
  local jar="${HOME}/.local/opt/apktool/apktool.jar"
  [[ -f "${jar}" ]] || { echo "[ERROR] missing jar: ${jar}"; return 3; }
  ls -lh "${jar}"

  echo "== OK =="
}

android_verify_jadx() {
  android_user_path_export

  echo "== jadx =="
  command -v jadx >/dev/null 2>&1 || { echo "[ERROR] jadx not found on PATH"; return 2; }
  jadx --version

  echo "== jadx-gui =="
  command -v jadx-gui >/dev/null 2>&1 || { echo "[ERROR] jadx-gui not found on PATH"; return 2; }
  jadx-gui --version

  echo "== paths =="
  command -v jadx jadx-gui

  echo "== install dir =="
  if [[ -d "${HOME}/.local/opt/jadx" ]]; then
    echo "[OK] ${HOME}/.local/opt/jadx exists"
  else
    echo "[ERROR] opt dir missing"
    return 3
  fi

  echo "== jar presence =="
  ls -lh "${HOME}/.local/opt/jadx/lib/"*.jar 2>/dev/null | head || {
    echo "[WARN] no jars under lib/"
  }

  echo "== OK =="
}

android_verify_smali() {
  android_user_path_export

  echo "== smali =="
  command -v smali >/dev/null 2>&1 || { echo "[ERROR] smali not found on PATH"; return 2; }
  smali --version

  echo "== baksmali =="
  command -v baksmali >/dev/null 2>&1 || { echo "[ERROR] baksmali not found on PATH"; return 2; }
  baksmali --version

  echo "== paths =="
  command -v smali baksmali

  echo "== jars =="
  shopt -s nullglob
  local jars=( "${HOME}/.local/opt/smali/"*.jar )
  shopt -u nullglob
  if ((${#jars[@]} == 0)); then
    echo "[ERROR] no jars under ${HOME}/.local/opt/smali/"
    return 3
  fi
  ls -lh "${jars[@]}"

  echo "== OK =="
}

android_verify_dex2jar() {
  android_user_path_export

  echo "== dex2jar (d2j tools) =="
  local tool found=0
  for tool in d2j-dex2jar d2j-jar2dex d2j-apk-sign; do
    if command -v "${tool}" >/dev/null 2>&1; then
      echo "[OK] ${tool}: $(command -v "${tool}")"
      found=$((found + 1))
    else
      echo "[ERROR] ${tool} not found on PATH"
    fi
  done

  echo "== install dir =="
  if [[ -d "${HOME}/.local/opt/dex2jar/current" ]]; then
    echo "[OK] ${HOME}/.local/opt/dex2jar/current exists"
  else
    echo "[ERROR] dex2jar install dir missing"
    return 3
  fi

  if (( found == 0 )); then
    return 2
  fi
  if (( found < 3 )); then
    return 2
  fi

  if command -v d2j-dex2jar >/dev/null 2>&1 && d2j-dex2jar -h >/dev/null 2>&1; then
    echo "[OK] d2j-dex2jar runnable"
  elif command -v d2j-dex2jar.sh >/dev/null 2>&1 && d2j-dex2jar.sh -h >/dev/null 2>&1; then
    echo "[OK] d2j-dex2jar.sh runnable"
  else
    echo "[WARN] d2j-dex2jar present but did not run cleanly"
  fi

  echo "== linked tools =="
  local f found=0 count=0 max_show=8
  shopt -s nullglob
  for f in "${HOME}/.local/bin"/d2j-*; do
    [[ "${f}" == *.bat ]] && continue
    count=$((count + 1))
    if (( count <= max_show )); then
      printf '  %s\n' "${f}"
      found=1
    fi
  done
  shopt -u nullglob
  if (( count > max_show )); then
    printf '  ... and %d more d2j-* tools in ~/.local/bin\n' "$(( count - max_show ))"
    found=1
  fi
  (( found )) || echo "  (none)"

  echo "== OK =="
}

android_verify_all_re_tools() {
  local rc=0
  local -a names=(apktool jadx "smali/baksmali" dex2jar)
  local -a fns=(android_verify_apktool android_verify_jadx android_verify_smali android_verify_dex2jar)
  local i name fn

  for i in "${!names[@]}"; do
    name="${names[$i]}"
    fn="${fns[$i]}"
    echo "--------------------------------------------------"
    echo "Verify: ${name}"
    echo "--------------------------------------------------"
    if ! "${fn}"; then
      rc=1
    fi
    echo
  done

  if (( rc == 0 )); then
    echo "[OK] All Android RE tools verified."
  else
    echo "[WARN] One or more Android RE tools failed verification."
  fi
  return "${rc}"
}

# ---------- ADB / core tooling ----------
android_check_version() {
  local label="$1"
  shift
  local bin="$1"

  if ! have "${bin}"; then
    printf '  [--] %-12s not installed\n' "${label}:"
    return 0
  fi

  local raw line=""
  raw="$("$@" 2>&1)" || true
  if [[ -z "${raw}" ]]; then
    printf '  [WARN] %-12s no version output\n' "${label}:"
    return 0
  fi
  if grep -qiE 'traceback \(most recent|modulenotfounderror|importerror|no such option' <<< "${raw}"; then
    line="$(printf '%s\n' "${raw}" | sed -n '/./p' | grep -iE 'modulenotfounderror|importerror|no such option' | head -n 1 || true)"
    [[ -n "${line}" ]] || line="$(printf '%s\n' "${raw}" | sed -n '/./p' | tail -n 1)"
    printf '  [WARN] %-12s broken (%s)\n' "${label}:" "${line}"
    if [[ "${label}" == "Mitmproxy" ]]; then
      printf '         [HINT] pip3 install --upgrade --force-reinstall mitmproxy\n'
    fi
    return 0
  fi
  line="$(printf '%s\n' "${raw}" | sed -n '/./p' | tail -n 1)"
  if [[ -n "${line}" ]]; then
    printf '  [OK] %-12s %s\n' "${label}:" "${line}"
  else
    printf '  [WARN] %-12s no version output\n' "${label}:"
  fi
}

android_core_tool_status() {
  local rc=0
  if ! have java; then
    warn "Java not on PATH (install java-21-openjdk)"
    rc=1
  fi
  android_check_version Java java -version
  android_check_version Python3 python3 --version
  android_check_version Frida frida --version
  android_check_version Objection objection version
  android_check_version Mitmproxy mitmproxy --version
  if ! have sdkmanager; then
    warn "sdkmanager not on PATH (run android_dev_core_setup.sh)"
    rc=1
  else
    android_check_version sdkmanager sdkmanager --version
  fi
  return "${rc}"
}

android_adb_status() {
  echo "== ADB =="
  if ! have adb; then
    echo "[ERROR] adb not found on PATH"
    echo "[HINT] Install android-tools (dnf) or run android_dev_core_setup.sh"
    return 2
  fi

  echo "Path: $(command -v adb)"
  adb version 2>&1 | head -n 2

  echo
  echo "== Connected devices =="
  adb devices -l

  echo
  echo "== USB / udev hints =="
  if [[ -d /etc/udev/rules.d ]]; then
    local rules
    rules="$(grep -l 'android\|adb' /etc/udev/rules.d/*.rules 2>/dev/null | head -n 3 || true)"
    if [[ -n "${rules}" ]]; then
      echo "[OK] Found udev rules:"
      printf '  %s\n' ${rules}
    else
      echo "[WARN] No obvious Android udev rules in /etc/udev/rules.d/"
      echo "[HINT] Fedora usually ships android-tools; replug device after setup."
    fi
  fi
}

doctor_android_research() {
  local rc=0

  echo "============================================================"
  echo "Android Research Workstation Doctor"
  echo "Host: $(hostname)  User: $(real_user)"
  echo "============================================================"
  echo

  echo "== Core tooling =="
  android_core_tool_status || rc=1
  echo

  android_adb_status || rc=1
  echo

  echo "== Reverse-engineering tools =="
  android_verify_all_re_tools || rc=1

  echo "============================================================"
  if (( rc == 0 )); then
    echo "Result: READY (all checks passed)"
  else
    echo "Result: ISSUES FOUND (review output above)"
  fi
  echo "============================================================"
  return "${rc}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
