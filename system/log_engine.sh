#!/usr/bin/env bash
# log_engine.sh — Logging engine CLI (inspect, tail, archive, summarize)
# Version: 0.2.2
#
# Run:
#   ./log_engine.sh status
#   ./log_engine.sh --file fedora_rebuild.log summary
#   ./log_engine.sh tail --file system_update.log --lines 50

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/logging.sh
source "${_SCRIPT_DIR}/../lib/logging.sh"

LOG_NAME="${FEDORA_LOG_SYSTEM_UPDATE}"
LINES=50
MAX_MB=10
CMD=""
POSITIONAL=()

usage() {
  cat <<EOF
Fedora logging engine CLI

Usage: $(basename "$0") [options] COMMAND [options]

Global options may appear before or after COMMAND.

Commands:
  status              Show engine state (env vars, active log)
  list                List operational logs, archive, backups
  summary             Session/error counts for a log file
  tail                Print last N lines (default: 50)
  follow              Follow log (tail -f)
  sessions            Show SESSION START/END markers
  issues              Grep ERROR/WARN/FAILED lines
  archive             Copy log to logs/archive/ (keeps original)
  truncate            Empty log file in place
  rotate              Archive then truncate if over --max-mb

Options:
  --file, -f NAME     Log filename (default: system_update.log)
  --lines, -n N       Lines for tail/issues (default: 50)
  --max-mb N          Size threshold for rotate (default: 10)
  --help, -h          Show this help

Examples:
  $(basename "$0") summary --file system_update.log
  $(basename "$0") --file fedora_rebuild.log issues --lines 100
  $(basename "$0") rotate --file system_update.log --max-mb 5
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file|-f)
      LOG_NAME="${2:?filename required}"
      shift 2
      ;;
    --lines|-n)
      LINES="${2:?line count required}"
      shift 2
      ;;
    --max-mb)
      MAX_MB="${2:?max megabytes required}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      POSITIONAL+=("$@")
      break
      ;;
    -*)
      err "Unknown option: $1 (try --help)"
      exit 2
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

[[ "${LINES}" =~ ^[0-9]+$ ]] || die "--lines must be a positive integer (got: ${LINES})"
[[ "${MAX_MB}" =~ ^[0-9]+$ ]] || die "--max-mb must be a positive integer (got: ${MAX_MB})"

CMD="${POSITIONAL[0]:-help}"
if ((${#POSITIONAL[@]} > 1)); then
  err "Unexpected arguments: ${POSITIONAL[*]:1}"
  exit 2
fi

case "${CMD}" in
  status)
    log_engine_status
    ;;
  list)
    log_list_files
    ;;
  summary)
    log_summary "${LOG_NAME}"
    ;;
  tail)
    log_tail_file "${LOG_NAME}" "${LINES}" 0
    ;;
  follow)
    log_tail_file "${LOG_NAME}" "${LINES}" 1
    ;;
  sessions)
    log_show_sessions "${LOG_NAME}"
    ;;
  issues|errors)
    log_grep_issues "${LOG_NAME}" "${LINES}"
    ;;
  archive)
    log_archive_file "${LOG_NAME}"
    ;;
  truncate)
    log_truncate_file "${LOG_NAME}"
    ;;
  rotate)
    log_rotate_if_large "${LOG_NAME}" "${MAX_MB}"
    ;;
  help)
    usage
    ;;
  *)
    err "Unknown command: ${CMD}"
    usage >&2
    exit 2
    ;;
esac
