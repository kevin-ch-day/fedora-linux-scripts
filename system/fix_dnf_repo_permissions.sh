#!/usr/bin/env bash
# fix_dnf_repo_permissions.sh — chmod 644 repo files unreadable to invoking user
# Version: 0.1.1
#
# Run:
#   sudo ./system/fix_dnf_repo_permissions.sh
#   sudo ./fedora.sh --fix-repos

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${_SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/baseline.sh
source "${FEDORA_ROOT}/lib/baseline.sh"
# shellcheck source=../lib/packages.sh
source "${FEDORA_ROOT}/lib/packages.sh"
# shellcheck source=../lib/theme.sh
source "${FEDORA_ROOT}/lib/theme.sh"
theme_init

usage() {
  cat <<EOF
Usage: sudo $(basename "$0") [--help]

Fix /etc/yum.repos.d/*.repo permissions so user-level dnf check works
(e.g. virtualbox.repo left at mode 600 after a third-party installer).

Also: ./fedora.sh --fix-repos
     System → [7] Cleanup → [6] Fix DNF repo permissions

Toolkit root: ${FEDORA_ROOT}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

require_root "Run with sudo: sudo ./fedora.sh --fix-repos"

invoker="${SUDO_USER:-${FEDORA_REAL_USER:-}}"
theme_banner "Fix DNF repo permissions"
theme_meta_line "Invoker: ${invoker:-root}"
theme_rule '─'
echo

unreadable="$(baseline_unreadable_repo_files || true)"
if [[ -z "${unreadable}" ]]; then
  ok "All .repo files readable — nothing to fix"
else
  info "Unreadable before fix:"
  printf '%s\n' "${unreadable}" | sed 's/^/  /'
  echo
  packages_fix_repo_permissions
fi

echo
if [[ -n "${invoker}" && "${invoker}" != root ]]; then
  if sudo -u "${invoker}" dnf check >/dev/null 2>&1; then
    ok "dnf check: OK (as ${invoker})"
    theme_summary_box "Summary" \
      "Result:  FIXED" \
      "Next:    ./fedora.sh --rebuild-check"
    exit 0
  fi
  warn "dnf check still fails (as ${invoker})"
  sudo -u "${invoker}" dnf check 2>&1 | head -n 3 | sed 's/^/  /' || true
  exit 1
fi

if dnf check >/dev/null 2>&1; then
  ok "dnf check: OK"
  exit 0
fi
warn "dnf check still fails"
dnf check 2>&1 | head -n 3 | sed 's/^/  /' || true
exit 1
