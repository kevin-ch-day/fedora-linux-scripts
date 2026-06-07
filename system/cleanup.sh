#!/usr/bin/env bash
# cleanup.sh — Safe cleanup for caches and toolkit logs
# Version: 0.3.2
#
# Run:
#   ./cleanup.sh
#   sudo ./cleanup.sh --dnf
#   ./cleanup.sh --truncate-logs
#   ./cleanup.sh --all-logs              # truncates every logs/*.log
#   ./cleanup.sh --truncate-logs --all-logs
#   ./cleanup.sh --archive --file system_update.log
#   ./cleanup.sh --rotate --file system_update.log --max-mb 10

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/packages.sh
source "${_SCRIPT_DIR}/../lib/packages.sh"
# shellcheck source=../lib/logging.sh
source "${_SCRIPT_DIR}/../lib/logging.sh"

DO_DNF=0
TRUNCATE_LOGS=0
TRUNCATE_ALL=0
DO_ARCHIVE=0
DO_ROTATE=0
QUIET=0
LOG_NAME="${FEDORA_LOG_SYSTEM_UPDATE}"
MAX_MB=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dnf)
      DO_DNF=1
      shift
      ;;
    --truncate-logs)
      TRUNCATE_LOGS=1
      shift
      ;;
    --all-logs)
      TRUNCATE_ALL=1
      TRUNCATE_LOGS=1
      shift
      ;;
    --archive)
      DO_ARCHIVE=1
      shift
      ;;
    --rotate)
      DO_ROTATE=1
      shift
      ;;
    --file|-f)
      LOG_NAME="${2:?filename required}"
      shift 2
      ;;
    --max-mb)
      MAX_MB="${2:-10}"
      shift 2
      ;;
    --quiet|-q)
      QUIET=1
      shift
      ;;
    --help|-h)
      cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --dnf              Clean DNF caches (sudo)
  --truncate-logs    Truncate one log (--file NAME, default: system_update.log)
  --all-logs         Truncate every logs/*.log (implies --truncate-logs)
  --archive          Archive --file to logs/archive/
  --rotate           Rotate --file if over --max-mb
  --file, -f NAME    Log basename (default: ${FEDORA_LOG_SYSTEM_UPDATE})
  --max-mb N         Rotate threshold MB (default: 10)
  --quiet, -q        Skip post-action log listing (menu-friendly)
  --help, -h         Show this help
EOF
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

if ! (( QUIET )); then
  info "Fedora toolkit cleanup"
fi

if (( DO_DNF )); then
  info "Cleaning DNF caches..."
  if [[ "${EUID}" -eq 0 ]]; then
    dnf_clean_all
  else
    sudo dnf clean all -y
  fi
  ok "DNF caches cleaned"
fi

if (( TRUNCATE_LOGS )); then
  if (( TRUNCATE_ALL )); then
    info "Truncating all operational .log files..."
    shopt -s nullglob
    for f in "$(log_dir)"/*.log; do
      log_truncate_file "$(basename "$f")"
    done
    shopt -u nullglob
  else
    log_truncate_file "${LOG_NAME}"
  fi
fi

if (( DO_ARCHIVE )); then
  info "Archiving ${LOG_NAME}..."
  log_archive_file "${LOG_NAME}"
fi

if (( DO_ROTATE )); then
  info "Rotating ${LOG_NAME} if over ${MAX_MB}MB..."
  log_rotate_if_large "${LOG_NAME}" "${MAX_MB}"
fi

if ! (( QUIET )); then
  log_list_files 2>/dev/null || true

  if have journalctl; then
    echo
    info "Journal disk usage (hint):"
    journalctl --disk-usage 2>/dev/null || true
    echo "[HINT] sudo journalctl --vacuum-time=7d"
  fi
fi

ok "Cleanup finished"
