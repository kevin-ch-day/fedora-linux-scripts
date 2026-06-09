#!/usr/bin/env bash
# fresh_install_check.sh — host baseline report after fresh Fedora install
# Version: 0.2.0
#
# Run:
#   ./system/fresh_install_check.sh
#   ./run.sh --baseline
#
# Read-only. Writes timestamped report under logs/.

set -uo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${_SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/baseline.sh
source "${FEDORA_ROOT}/lib/baseline.sh"
# shellcheck source=../lib/theme.sh
source "${FEDORA_ROOT}/lib/theme.sh"
theme_init

usage() {
  cat <<EOF
Usage: $(basename "$0") [--help]

Collect a read-only host baseline after a fresh Fedora install.
Prints to the terminal and saves:

  logs/fresh_install_check_YYYYMMDD_HHMMSS.log

Also: ./run.sh --baseline

Toolkit root: ${FEDORA_ROOT}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

STAMP="$(date +%Y%m%d_%H%M%S)"
ensure_log_dir
REPORT_FILE="$(log_dir)/fresh_install_check_${STAMP}.log"

exec > >(tee -a "${REPORT_FILE}") 2>&1

theme_banner "Fresh install baseline check"
theme_meta_line "Host: $(health_hostname) · User: $(real_user)"
theme_meta_line "Started: $(date -Is)"
theme_meta_line "Report:  ${REPORT_FILE}"
theme_rule '─'

baseline_collect_fresh_install
baseline_print_fresh_summary

MISSING_CORE=0
for cmd in git python3 pip3 gcc java curl wget; do
  have "${cmd}" || MISSING_CORE=$((MISSING_CORE + 1))
done

theme_summary_box "Summary" \
  "Report:     ${REPORT_FILE}" \
  "Host:       $(health_hostname)" \
  "Fedora:     $(baseline_fedora_release_line)" \
  "Core tools: $(( 7 - MISSING_CORE ))/7 common commands present" \
  "Next step:  ./run.sh --rebuild-check" \
  "            then ./run.sh --rebuild when ready"
exit 0
