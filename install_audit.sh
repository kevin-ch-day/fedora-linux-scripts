#!/usr/bin/env bash
# install_audit.sh — Static + helper tests for all install targets
# Version: 0.1.1
#
# Run from repo root:
#   ./install_audit.sh
#   ./install_audit.sh --quick    # skip live pkg_present checks
#   ./install_audit.sh --help

set -uo pipefail

AUDIT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${AUDIT_ROOT}/lib/common.sh"
# shellcheck source=lib/packages.sh
source "${AUDIT_ROOT}/lib/packages.sh"

QUICK=0
FAILURES=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Audit install scripts and package helpers for common failure patterns
(e.g. sudo PATH vs dnf_installed mismatch).

Options:
  --quick       Skip live host checks (installed RPM vs binary path)
  --help, -h    Show this help

Checks:
  - Inventory of install scripts and mechanisms
  - bash -n on each install script
  - --help smoke (non-interactive)
  - Anti-patterns: post-install \`have\` without pkg_present
  - pkg_present / pkg_binary_path unit tests (mocked)
  - Live: common tools when RPM is installed
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --quick) QUICK=1; shift ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

_audit_pkg_installed() {
  dnf_installed "$1" 2>/dev/null
}

_audit_fail() {
  warn "$*"
  FAILURES=$((FAILURES + 1))
}

_audit_ok() {
  ok "$*"
}

# Install scripts grouped by lane (paths relative to repo root).
INSTALL_SCRIPTS=(
  dev/install_vscode.sh
  dev/git_setup.sh
  dev/lamp_python_setup.sh
  dev/phpmyadmin_setup.sh
  dev/desktop_setup.sh
  dev/fedora_container_kvm_setup.sh
  mobsf/mobsf_install.sh
  android/android_dev_core_setup.sh
  android/android_re_install.sh
)

declare -A INSTALL_MECHANISM=(
  [dev/install_vscode.sh]="dnf (Microsoft repo) · pkg_install_if_missing code"
  [dev/git_setup.sh]="pkg_install_cmd_if_missing git"
  [dev/lamp_python_setup.sh]="pkg_install_if_missing httpd mariadb php* python3"
  [dev/phpmyadmin_setup.sh]="pkg_install_if_missing (web stack deps)"
  [dev/desktop_setup.sh]="pkg_install_batch_if_available · @cinnamon-desktop"
  [dev/fedora_container_kvm_setup.sh]="pkg_install_optional podman docker libvirt"
  [mobsf/mobsf_install.sh]="pkg_install_cmd_if_missing podman podman-compose curl"
  [android/android_dev_core_setup.sh]="dnf batch · flatpak · pip user"
  [android/android_re_install.sh]="user-scope downloads (lib/android_re.sh)"
)

# shellcheck source=lib/theme.sh
source "${AUDIT_ROOT}/lib/theme.sh"
theme_init
theme_set_lane audit

theme_lane_banner "Install audit" audit
theme_meta_line "Root: ${AUDIT_ROOT}"
theme_rule '─'
echo

theme_report_section "Install inventory (${#INSTALL_SCRIPTS[@]} scripts)"
for rel in "${INSTALL_SCRIPTS[@]}"; do
  path="${AUDIT_ROOT}/${rel}"
  if [[ -f "${path}" ]]; then
    theme_note_kv "${rel}" "${INSTALL_MECHANISM[${rel}]:-unknown}"
  else
    _audit_fail "missing install script: ${rel}"
  fi
done

theme_report_section "Syntax (bash -n)"
for rel in "${INSTALL_SCRIPTS[@]}"; do
  path="${AUDIT_ROOT}/${rel}"
  [[ -f "${path}" ]] || continue
  if bash -n "${path}" 2>/dev/null; then
    _audit_ok "bash -n: ${rel}"
  else
    _audit_fail "bash -n failed: ${rel}"
  fi
done

theme_report_section "--help smoke"
for rel in "${INSTALL_SCRIPTS[@]}"; do
  path="${AUDIT_ROOT}/${rel}"
  [[ -f "${path}" ]] || continue
  if bash "${path}" --help >/dev/null 2>&1; then
    _audit_ok "--help: ${rel}"
  else
    _audit_fail "--help failed: ${rel}"
  fi
done

theme_report_section "Anti-pattern scan (post-install PATH-only checks)"
# Scripts that should use pkg_present/pkg_binary_path after dnf install, not bare have.
RISKY_PATTERNS=(
  'have code'
  'have docker'
  'have podman'
  'have git'
  'have pip3'
  'have flatpak'
)
for rel in "${INSTALL_SCRIPTS[@]}"; do
  path="${AUDIT_ROOT}/${rel}"
  [[ -f "${path}" ]] || continue
  found=0
  for pat in "${RISKY_PATTERNS[@]}"; do
    if grep -qF "${pat}" "${path}" 2>/dev/null; then
      # Allow have in non-post-install contexts (e.g. service checks)
      if grep -nF "${pat}" "${path}" | grep -qvE 'systemctl|warn|optional|npm'; then
        printf '  note %s: contains '\''%s'\'' — verify sudo PATH-safe\n' "${rel}" "${pat}"
        found=1
      fi
    fi
  done
  if (( found == 0 )); then
    _audit_ok "no risky bare-have post-install: ${rel}"
  fi
done

# lib/packages.sh must use pkg_present in cmd installer
if grep -q 'pkg_present' "${AUDIT_ROOT}/lib/packages.sh" \
  && grep -A6 'pkg_install_cmd_if_missing' "${AUDIT_ROOT}/lib/packages.sh" | grep -q 'pkg_present'; then
  _audit_ok "pkg_install_cmd_if_missing uses pkg_present"
else
  _audit_fail "pkg_install_cmd_if_missing missing pkg_present guard"
fi

if grep -A2 'need_cmd()' "${AUDIT_ROOT}/lib/common.sh" | grep -q 'cmd_available'; then
  _audit_ok "need_cmd uses cmd_available (sudo PATH-safe)"
else
  _audit_fail "need_cmd still uses have-only check"
fi

if grep -A3 'pkg_install_optional' "${AUDIT_ROOT}/lib/packages.sh" | grep -q 'pkg_present'; then
  _audit_ok "pkg_install_optional uses pkg_present"
else
  _audit_fail "pkg_install_optional missing pkg_present guard"
fi

theme_report_section "pkg_present / pkg_binary_path unit tests (mocked)"

_audit_test_result() {
  local label="$1"
  local expect="$2"
  local rc="$3"
  if [[ "${expect}" == pass && "${rc}" -eq 0 ]] || [[ "${expect}" == fail && "${rc}" -ne 0 ]]; then
    _audit_ok "mock: ${label}"
  else
    _audit_fail "mock: ${label} (expected ${expect}, got rc=${rc})"
  fi
}

# Mock: RPM installed, no binary on PATH — pkg_present should still pass
_audit_pkg_present_rpm_only() (
  # shellcheck source=lib/packages.sh
  source "${AUDIT_ROOT}/lib/packages.sh"
  dnf_installed() { [[ "$1" == mockpkg ]]; }
  pkg_binary_path() { return 1; }
  pkg_present mockpkg mockbin
)

# Mock: httpd in /usr/sbin only
_audit_pkg_present_sbin() (
  # shellcheck source=lib/packages.sh
  source "${AUDIT_ROOT}/lib/packages.sh"
  dnf_installed() { return 1; }
  pkg_binary_path() {
    [[ "$1" == httpd ]] && { printf '/usr/sbin/httpd\n'; return 0; }
    return 1
  }
  pkg_present httpd httpd
)

if _audit_pkg_present_rpm_only; then
  _audit_test_result "rpm-only pkg_present" pass 0
else
  _audit_test_result "rpm-only pkg_present" pass 1
fi

if _audit_pkg_present_sbin; then
  _audit_test_result "usr/sbin httpd via pkg_binary_path" pass 0
else
  _audit_test_result "usr/sbin httpd via pkg_binary_path" pass 1
fi

rc=0
pkg_binary_path definitely-not-a-real-binary-xyz >/dev/null 2>&1 || rc=$?
_audit_test_result "pkg_binary_path rejects missing" fail "${rc}"

rc=0
cmd_binary_path definitely-not-a-real-binary-xyz >/dev/null 2>&1 || rc=$?
_audit_test_result "cmd_binary_path rejects missing" fail "${rc}"

# cmd_binary_path finds standard sbin layout when not on PATH
_audit_cmd_sbin_mock() (
  command() {
    if [[ "${1:-}" == "-v" ]]; then return 1; fi
    builtin command "$@"
  }
  if [[ ! -x /usr/sbin/httpd && ! -x /usr/bin/httpd ]]; then
    return 2
  fi
  cmd_binary_path httpd
)
mock_rc=0
out="$(_audit_cmd_sbin_mock 2>/dev/null)" || mock_rc=$?
if [[ "${mock_rc}" -eq 2 ]]; then
  _audit_ok "cmd_binary_path httpd test skipped (httpd not installed)"
elif [[ "${mock_rc}" -eq 0 && -n "${out}" ]]; then
  _audit_ok "cmd_binary_path resolves httpd (${out})"
else
  _audit_fail "cmd_binary_path could not resolve httpd (${out:-empty}, rc=${mock_rc})"
fi

if pkg_present python3 python3 2>/dev/null; then
  bp="$(pkg_binary_path python3 2>/dev/null || true)"
  _audit_ok "live: python3 present (${bp:-path unknown})"
elif _audit_pkg_installed python3 2>/dev/null; then
  _audit_fail "live: python3 RPM installed but pkg_present failed (PATH/sbin bug?)"
fi

if pkg_present code code 2>/dev/null; then
  _audit_ok "live: VS Code (code) pkg_present OK"
elif _audit_pkg_installed code 2>/dev/null; then
  _audit_fail "live: code RPM installed but pkg_present failed — VS Code sudo bug class"
fi

if (( QUICK == 0 )); then
  theme_report_section "Live host checks (RPM vs binary)"
  LIVE_PKGS=(
    "git:git"
    "podman:podman"
    "curl:curl"
    "python3:python3"
    "python3-pip:pip3"
    "httpd:httpd"
    "mariadb:mysql"
    "php:php"
  )
  for pair in "${LIVE_PKGS[@]}"; do
    pkg="${pair%%:*}"
    bin="${pair##*:}"
    if _audit_pkg_installed "${pkg}" 2>/dev/null; then
      if pkg_present "${pkg}" "${bin}" 2>/dev/null; then
        bp="$(pkg_binary_path "${bin}" 2>/dev/null || echo unknown)"
        _audit_ok "installed ${pkg} → ${bin} at ${bp}"
      else
        _audit_fail "installed ${pkg} but pkg_present ${bin} failed (sudo PATH class bug)"
      fi
    else
      theme_tool_row skip "${pkg}" "not installed on this host"
    fi
  done
else
  theme_note "Skipping live host checks (--quick)"
fi

echo
if (( FAILURES == 0 )); then
  theme_summary_box "Install audit summary" \
    "Result: passed" \
    "Issues: 0" \
    "Next: ./validate.sh --install-audit"
  exit 0
fi
theme_summary_box "Install audit summary" \
  "Result: FAILED" \
  "Issues: ${FAILURES}" \
  "Next: fix install scripts above"
err "Install audit failed (${FAILURES} issue(s))"
exit 1
