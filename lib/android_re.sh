#!/usr/bin/env bash
# lib/android_re.sh — shared Android RE user-scope install helpers
# Version: 0.1.2
#
# Source from install scripts:
#   source "${_dir}/../lib/android_re.sh"
#   android_re_install_apktool
#
# Do not execute directly.

if [[ -n "${FEDORA_ANDROID_RE_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_ANDROID_RE_SH_LOADED=1

_ANDROID_RE_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=packages.sh
source "${_ANDROID_RE_LIB_DIR}/packages.sh"
# shellcheck source=android.sh
source "${_ANDROID_RE_LIB_DIR}/android.sh"

android_re_home() {
  real_home
}

android_re_bin_dir() {
  printf '%s/.local/bin\n' "$(android_re_home)"
}

android_re_opt_dir() {
  local name="$1"
  printf '%s/.local/opt/%s\n' "$(android_re_home)" "${name}"
}

android_re_prepare_base() {
  pkg_install_cmd_if_missing curl curl
  need_cmd python3
  ensure_user_bin_on_path
}

android_re_prepare_unzip() {
  android_re_prepare_base
  pkg_install_cmd_if_missing unzip unzip
}

android_re_post_verify() {
  local fn="$1"
  local label="${2:-${fn#android_verify_}}"
  echo
  info "Post-install verification..."
  android_verify_as_user "${fn}" || die_with_hint \
    "${label} verification failed" \
    "Retry: ./android/android_re_install.sh ${label}  then  ./android/verify_re_tool.sh ${label}"
  ok "Post-install verification complete"
}

android_re_write_java_jar_wrapper() {
  local wrapper="$1"
  local jar_abs="$2"

  run_as_real_user tee "${wrapper}" > /dev/null <<EOF
#!/usr/bin/env bash
set -euo pipefail
JAR="${jar_abs}"
[[ -f "\$JAR" ]] || { echo "[ERROR] jar missing: \$JAR" >&2; exit 2; }
exec java -jar "\$JAR" "\$@"
EOF
  run_as_real_user chmod +x "${wrapper}"
}

android_re_write_java_jar_wrapper_home_rel() {
  local wrapper="$1"
  local jar_home_rel="$2"

  run_as_real_user tee "${wrapper}" > /dev/null <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec java -jar "\$HOME/${jar_home_rel}" "\$@"
EOF
  run_as_real_user chmod +x "${wrapper}"
}

android_re_release_asset_url() {
  local repo="$1"
  local pattern="$2"
  local json url

  json="$(android_github_release_json "${repo}")" || return 1
  url="$(android_github_pick_asset_url "${json}" "${pattern}" 2>/dev/null || true)"
  [[ -n "${url}" ]] || return 1
  printf '%s\n' "${url}"
}

android_re_with_tempdir() {
  (
    set -euo pipefail
    local tmp=""
    errors_mktemp_dir tmp
    "$@" "${tmp}"
  )
}

# ---------- apktool ----------
android_re_install_apktool() {
  local home opt_dir jar_path bin_dir wrapper

  home="$(android_re_home)"
  opt_dir="$(android_re_opt_dir apktool)"
  jar_path="${opt_dir}/apktool.jar"
  bin_dir="${home}/.local/bin"
  wrapper="${bin_dir}/apktool"

  if [[ -x "${wrapper}" && -f "${jar_path}" ]]; then
    ok "apktool appears installed already: ${wrapper}"
    android_re_post_verify android_verify_apktool apktool
    return 0
  fi

  android_re_prepare_base
  run_as_real_user mkdir -p "${opt_dir}" "${bin_dir}"

  android_re_with_tempdir _android_re_install_apktool_download "${jar_path}" "${wrapper}"
  ok "Installed: ${wrapper}"
  android_re_post_verify android_verify_apktool apktool
  echo "[NEXT] apktool --version  (source ~/.bashrc if needed)"
}

_android_re_install_apktool_download() {
  local tmp="$1"
  local jar_path="$2"
  local wrapper="$3"
  local jar_tmp="${tmp}/apktool.jar"
  local url url_candidates=() download_ok=0 u

  info "Resolving latest apktool jar URL..."
  if url="$(android_re_release_asset_url "iBotPeaches/Apktool" '^apktool_.*\.jar$' 2>/dev/null || true)"; then
    url_candidates=("${url}")
  else
    warn "GitHub API lookup failed — falling back to known mirrors."
    url_candidates=(
      "https://sourceforge.net/projects/apktool.mirror/files/apktool_2.12.1.jar/download"
      "https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_2.12.1.jar"
    )
  fi

  for u in "${url_candidates[@]}"; do
    if android_user_download "${u}" "${jar_tmp}"; then
      download_ok=1
      break
    fi
  done
  (( download_ok == 1 )) || die "Failed to download apktool jar"

  run_as_real_user mv -f "${jar_tmp}" "${jar_path}"
  run_as_real_user chmod 0644 "${jar_path}" 2>/dev/null || true
  android_re_write_java_jar_wrapper "${wrapper}" "${jar_path}"
}

# ---------- jadx ----------
android_re_install_jadx() {
  local home opt_dir bin_dir jadx_bin jadx_gui_bin

  home="$(android_re_home)"
  opt_dir="$(android_re_opt_dir jadx)"
  bin_dir="${home}/.local/bin"
  jadx_bin="${bin_dir}/jadx"
  jadx_gui_bin="${bin_dir}/jadx-gui"

  if [[ -x "${jadx_bin}" ]]; then
    ok "jadx already installed (user scope): ${jadx_bin}"
    android_re_post_verify android_verify_jadx jadx
    echo "[NEXT] jadx --version"
    echo "[NEXT] jadx-gui (optional)"
    return 0
  fi

  android_re_prepare_unzip
  android_re_with_tempdir _android_re_install_jadx_download "${opt_dir}" "${jadx_bin}" "${jadx_gui_bin}"
  ok "jadx install complete (user scope)"
  android_re_post_verify android_verify_jadx jadx
  echo "[NEXT] jadx --version"
  echo "[NEXT] jadx-gui (optional)"
}

_android_re_install_jadx_download() {
  local tmp="$1"
  local opt_dir="$2"
  local jadx_bin="$3"
  local jadx_gui_bin="$4"
  local url zip jadx_real jadx_gui_real

  info "Fetching latest jadx release metadata (skylot/jadx)..."
  url="$(android_re_release_asset_url "skylot/jadx" '^jadx-.*\.zip$')" \
    || die "Could not find jadx zip asset. See: https://github.com/skylot/jadx/releases/latest"

  zip="${tmp}/jadx.zip"
  info "Downloading jadx zip..."
  android_user_download "${url}" "${zip}"
  ok "Downloaded: ${zip}"

  info "Installing into ${opt_dir} (user scope)..."
  run_as_real_user rm -rf "${opt_dir}"
  run_as_real_user mkdir -p "${opt_dir}"
  run_as_real_user unzip -q "${zip}" -d "${opt_dir}"

  jadx_real="$(find "${opt_dir}" -type f -path '*/bin/jadx' -print | head -n 1 || true)"
  jadx_gui_real="$(find "${opt_dir}" -type f -path '*/bin/jadx-gui' -print | head -n 1 || true)"
  [[ -n "${jadx_real}" ]] || die "jadx binary not found after unzip. Layout may have changed."

  run_as_real_user chmod +x "${jadx_real}" 2>/dev/null || true
  [[ -n "${jadx_gui_real}" ]] && run_as_real_user chmod +x "${jadx_gui_real}" 2>/dev/null || true

  run_as_real_user ln -sf "${jadx_real}" "${jadx_bin}"
  ok "Installed: ${jadx_bin}"

  if [[ -n "${jadx_gui_real}" ]]; then
    run_as_real_user ln -sf "${jadx_gui_real}" "${jadx_gui_bin}"
    ok "Installed: ${jadx_gui_bin}"
  else
    warn "jadx-gui not found in this release zip (CLI still installed)."
  fi
}

# ---------- smali / baksmali ----------
android_re_install_smali() {
  local home opt_dir bin_dir smali_jar baksmali_jar smali_bin baksmali_bin

  home="$(android_re_home)"
  opt_dir="$(android_re_opt_dir smali)"
  bin_dir="${home}/.local/bin"
  smali_jar="${opt_dir}/smali-fat.jar"
  baksmali_jar="${opt_dir}/baksmali-fat.jar"
  smali_bin="${bin_dir}/smali"
  baksmali_bin="${bin_dir}/baksmali"

  if [[ -x "${smali_bin}" && -x "${baksmali_bin}" && -s "${smali_jar}" && -s "${baksmali_jar}" ]]; then
    ok "smali/baksmali already installed (user scope)"
    android_re_post_verify android_verify_smali "smali/baksmali"
    return 0
  fi

  android_re_prepare_base
  need_cmd java
  run_as_real_user mkdir -p "${opt_dir}" "${bin_dir}"

  info "Fetching latest smali release metadata (baksmali/smali)..."
  local json smali_url baksmali_url
  json="$(android_github_release_json "baksmali/smali")" || die "Failed to fetch GitHub release JSON (rate limit?)"

  smali_url="$(android_github_pick_asset_url "$json" '^smali-.*-fat-release\.jar$' 2>/dev/null || true)"
  baksmali_url="$(android_github_pick_asset_url "$json" '^baksmali-.*-fat-release\.jar$' 2>/dev/null || true)"
  [[ -n "${smali_url}" ]] || smali_url="$(android_github_pick_asset_url "$json" '^smali-.*-fat\.jar$' 2>/dev/null || true)"
  [[ -n "${baksmali_url}" ]] || baksmali_url="$(android_github_pick_asset_url "$json" '^baksmali-.*-fat\.jar$' 2>/dev/null || true)"
  [[ -n "${smali_url}" && -n "${baksmali_url}" ]] \
    || die "Could not find smali/baksmali fat jar assets. See: https://github.com/baksmali/smali/releases/latest"

  info "Downloading smali fat jar..."
  android_user_download "${smali_url}" "${smali_jar}"
  ok "Downloaded: ${smali_jar}"

  info "Downloading baksmali fat jar..."
  android_user_download "${baksmali_url}" "${baksmali_jar}"
  ok "Downloaded: ${baksmali_jar}"

  android_re_write_java_jar_wrapper_home_rel "${smali_bin}" ".local/opt/smali/smali-fat.jar"
  ok "Wrapper installed: smali -> ${smali_bin}"
  android_re_write_java_jar_wrapper_home_rel "${baksmali_bin}" ".local/opt/smali/baksmali-fat.jar"
  ok "Wrapper installed: baksmali -> ${baksmali_bin}"

  [[ -s "${smali_jar}" && -s "${baksmali_jar}" ]] || die "Downloaded jar is empty (unexpected)"

  ok "smali/baksmali install complete (user scope)"
  android_re_post_verify android_verify_smali "smali/baksmali"
  echo "[NEXT] source ~/.bashrc (or restart shell)"
  echo "[CHECK] smali --version && baksmali --version"
}

# ---------- dex2jar ----------
android_re_d2j_cleanup_stale_bat_symlinks() {
  local bin_dir="$1"
  local removed=0 bat

  for bat in "${bin_dir}"/d2j-*.bat; do
    [[ -L "$bat" ]] || continue
    run_as_real_user rm -f "$bat"
    removed=$((removed + 1))
  done
  (( removed > 0 )) && ok "Removed stale .bat symlinks from ~/.local/bin (count: ${removed})"
}

android_re_d2j_find_tool_dir() {
  local opt_current="$1"
  local p
  p="$(find "${opt_current}" -maxdepth 6 -type f -name 'd2j-dex2jar.sh' -print | head -n 1 || true)"
  [[ -n "$p" ]] || return 1
  dirname "$p"
}

android_re_d2j_link_tools() {
  local tool_dir="$1"
  local bin_dir="$2"
  local linked=0 f base alias

  run_as_real_user mkdir -p "${bin_dir}"
  android_re_d2j_cleanup_stale_bat_symlinks "${bin_dir}"

  info "Linking d2j-* tools into ${bin_dir} (Linux only + aliases)..."

  shopt -s nullglob
  for f in "${tool_dir}"/d2j-*.sh; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    alias="${base%.sh}"

    run_as_real_user chmod +x "$f" 2>/dev/null || true
    run_as_real_user ln -sf "$f" "${bin_dir}/${base}"
    run_as_real_user ln -sf "$f" "${bin_dir}/${alias}"
    linked=$((linked + 1))
  done
  shopt -u nullglob

  (( linked > 0 )) || { warn "No d2j-*.sh scripts found in: ${tool_dir}"; return 1; }
  ok "Symlinks created in ${bin_dir} (linked scripts: ${linked}; +aliases without .sh)"
}

android_re_install_dex2jar() {
  local home opt_base opt_current bin_dir tool_dir

  home="$(android_re_home)"
  opt_base="${home}/.local/opt/dex2jar"
  opt_current="${opt_base}/current"
  bin_dir="${home}/.local/bin"

  export PATH="${bin_dir}:${PATH}"

  if [[ -d "${opt_current}" ]]; then
    ok "dex2jar appears installed already (user scope)"
    tool_dir="$(android_re_d2j_find_tool_dir "${opt_current}" || true)"
    if [[ -n "${tool_dir}" ]]; then
      info "Existing dex2jar install detected. Repairing symlinks in ~/.local/bin..."
      android_re_d2j_link_tools "${tool_dir}" "${bin_dir}" || true
    else
      warn "Existing install detected but could not locate d2j-dex2jar.sh under ${opt_current}"
    fi
    android_re_post_verify android_verify_dex2jar dex2jar
    echo "[NEXT] d2j-dex2jar -h"
    return 0
  fi

  android_re_prepare_unzip
  android_re_with_tempdir _android_re_install_dex2jar_download "${opt_base}" "${opt_current}" "${bin_dir}"
  ok "dex2jar (dex-tools) install complete (user scope)"
  android_re_post_verify android_verify_dex2jar dex2jar
  echo "[NEXT] d2j-dex2jar -h"
  echo "[NEXT] If command not found in new shells: source ~/.bashrc"
}

_android_re_install_dex2jar_download() {
  local tmp="$1"
  local opt_base="$2"
  local opt_current="$3"
  local bin_dir="$4"
  local url zip tool_dir

  info "Fetching latest dex2jar release metadata (pxb1988/dex2jar)..."
  url="$(android_re_release_asset_url "pxb1988/dex2jar" '^dex-tools-.*\.zip$')" \
    || die "Could not find dex-tools zip. See: https://github.com/pxb1988/dex2jar/releases/latest"

  zip="${tmp}/dex-tools.zip"
  info "Downloading dex-tools zip..."
  android_user_download "${url}" "${zip}"
  ok "Downloaded: ${zip}"

  info "Installing into ${opt_current} (user scope)..."
  run_as_real_user mkdir -p "${opt_base}"
  run_as_real_user rm -rf "${opt_current}"
  run_as_real_user mkdir -p "${opt_current}"
  run_as_real_user unzip -q "${zip}" -d "${opt_current}"

  tool_dir="$(android_re_d2j_find_tool_dir "${opt_current}" || true)"
  [[ -n "${tool_dir}" ]] || die "Could not find d2j-dex2jar.sh after unzip. Layout may have changed."

  android_re_d2j_link_tools "${tool_dir}" "${bin_dir}" || warn "Linking step had issues; continuing to verification."
}

# ---------- batch ----------
android_re_install_all() {
  local t fn rc=0
  errors_issue_reset
  for t in apktool jadx smali dex2jar; do
    echo
    info "=== Installing ${t} ==="
    case "${t}" in
      apktool) fn=android_re_install_apktool ;;
      jadx) fn=android_re_install_jadx ;;
      smali) fn=android_re_install_smali ;;
      dex2jar) fn=android_re_install_dex2jar ;;
    esac
    if ! "${fn}"; then
      rc=1
      errors_issue_add "${t}" "install failed"
      warn "${t} install failed — continuing with remaining tools"
    fi
  done
  if (( rc == 0 )); then
    ok "All RE tool installs finished"
  else
    errors_issue_summary "RE install failures" || true
    die_with_hint "Some RE tools failed to install" \
      "Retry individually: ./android/android_re_install.sh <tool>"
  fi
  echo "[NEXT] ./android/verify_re_tool.sh all"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
