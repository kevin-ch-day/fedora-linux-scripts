#!/usr/bin/env bash
# git_setup.sh — Configure Git identity and common preferences (invoker user)
# Version: 0.3.1
#
# Run:
#   ./dev/git_setup.sh
#   GIT_NAME="..." GIT_EMAIL="..." ./dev/git_setup.sh
#   ./dev/git_setup.sh --dry-run
#
# Do not run with sudo unless you intend to configure root's gitconfig.
# Prefer running as your normal user.

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/packages.sh
source "${_SCRIPT_DIR}/../lib/packages.sh"

DEFAULT_BRANCH="main"
FORCE=0
DRY_RUN=0
STATUS=0
GIT_NAME="${GIT_NAME:-${FEDORA_GIT_NAME:-}}"
GIT_EMAIL="${GIT_EMAIL:-${FEDORA_GIT_EMAIL:-}}"

git_as_user() {
  run_as_real_user git "$@"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Configure git for $(real_user) ($(real_home)/.gitconfig):
  user.name, user.email, init.defaultBranch, color.ui, core.editor, credential.helper

Options:
  --help, -h     Show this help
  --status       Show current global git config (no prompts)
  --force        Overwrite existing user.name / user.email
  --dry-run      Print planned changes without writing

Environment:
  GIT_NAME, GIT_EMAIL          Identity (prompted if unset)
  FEDORA_GIT_NAME, FEDORA_GIT_EMAIL   Alternate env names

Run as your normal user (not sudo).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --status) STATUS=1; shift ;;
    --force) FORCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
done

if (( STATUS )); then
  info "Git global config for $(real_user) ($(real_home)/.gitconfig)"
  if git_as_user config --global --list 2>/dev/null | sed 's/^/  /'; then
    :
  else
    warn "No global git config yet — run Git setup from the Dev menu"
  fi
  exit 0
fi

if [[ "${EUID}" -eq 0 && -z "${SUDO_USER:-}" ]]; then
  die "Run as your normal user, not root. Use: ./dev/git_setup.sh"
fi

if [[ -z "${GIT_NAME}" ]]; then
  read -r -p "Git user.name: " GIT_NAME
fi
if [[ -z "${GIT_EMAIL}" ]]; then
  read -r -p "Git user.email: " GIT_EMAIL
fi
[[ -n "${GIT_NAME}" ]] || die "Git user.name is required"
[[ -n "${GIT_EMAIL}" ]] || die "Git user.email is required"

info "Setting up Git for $(real_user)..."

if (( DRY_RUN )); then
  info "[dry-run] would install: git (if missing)"
  info "[dry-run] user.name=${GIT_NAME}"
  info "[dry-run] user.email=${GIT_EMAIL}"
  info "[dry-run] init.defaultBranch=${DEFAULT_BRANCH}"
  exit 0
fi

pkg_install_cmd_if_missing git git

_set_if_empty_or_force() {
  local key="$1"
  local value="$2"
  local current=""
  current="$(git_as_user config --global "${key}" 2>/dev/null || true)"
  if [[ -n "${current}" && "${FORCE}" -eq 0 ]]; then
    ok "${key} already set: ${current} (use --force to overwrite)"
    return 0
  fi
  git_as_user config --global "${key}" "${value}"
  ok "${key}=${value}"
}

_set_if_empty_or_force user.name "${GIT_NAME}"
_set_if_empty_or_force user.email "${GIT_EMAIL}"

git_as_user config --global init.defaultBranch "${DEFAULT_BRANCH}"
ok "init.defaultBranch=${DEFAULT_BRANCH}"

git_as_user config --global color.ui auto
git_as_user config --global core.editor "nano"
git_as_user config --global credential.helper cache

ok "Git setup complete for $(real_user)."
echo "Verify with: git config --global --list"
