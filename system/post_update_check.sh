#!/usr/bin/env bash
# post_update_check.sh — validation after dnf upgrade (read-only)
# Version: 0.1.2
#
# Exit 0 when stable; exit 1 when reboot, btrfs, services, or VirtualBox need review.
#
# Run:
#   ./system/post_update_check.sh
#   ./system/system.sh post-update-check

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${_SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/readiness.sh
source "${FEDORA_ROOT}/lib/readiness.sh"
theme_init
theme_set_lane audit

usage() {
  cat <<EOF
Usage: $(basename "$0") [--help]

Post-update validation after dnf upgrade:
  reboot need · btrfs stats · failed services · VirtualBox · package noise

Also: ./system/system.sh post-update-check

Toolkit root: ${FEDORA_ROOT}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

ISSUES=0

theme_report_header "Post-update check" \
  "Host: $(health_hostname) · Kernel: $(health_kernel)" \
  "Read-only validation after dnf upgrade"

theme_section "Reboot required"
while IFS= read -r line; do
  [[ -n "${line}" ]] && printf '  %s\n' "${line}"
done < <(readiness_reboot_status_text)
if readiness_reboot_needed; then
  warn "Reboot recommended"
  ISSUES=$((ISSUES + 1))
else
  ok "No reboot required"
fi

theme_section "Btrfs"
if readiness_root_is_btrfs; then
  stats="$(readiness_btrfs_device_stats / 2>/dev/null || true)"
  if [[ -n "${stats}" ]]; then
    printf '%s\n' "${stats}"
    if grep -qE 'corruption_errs[[:space:]]+[1-9]' <<< "${stats}"; then
      warn "Non-zero corruption_errs"
      ISSUES=$((ISSUES + 1))
    else
      ok "corruption_errs: 0"
    fi
  else
    warn "Could not read btrfs device stats"
    ISSUES=$((ISSUES + 1))
  fi
else
  theme_note "Root is not btrfs — skipped"
fi

theme_section "Failed systemd units"
failed="$(health_failed_systemd_units_count)"
theme_kv "Count" "${failed}"
if [[ "${failed}" != "0" ]]; then
  health_failed_systemd_units_list | sed 's/^/  /'
  ISSUES=$((ISSUES + 1))
else
  ok "No failed units"
fi

theme_section "VirtualBox"
if readiness_vbox_is_installed; then
  if [[ -n "$(readiness_vbox_modules_loaded)" ]]; then
    readiness_vbox_modules_loaded | sed 's/^/  /'
    if vbox_ver="$(readiness_vbox_version 2>/dev/null)"; then
      ok "VBoxManage: ${vbox_ver}"
    else
      warn "VBoxManage version unreadable (check /dev/vboxdrv and vboxdrv.service)"
      ISSUES=$((ISSUES + 1))
    fi
    if ! readiness_vbox_char_dev_ready; then
      warn "/dev/vboxdrv missing — VirtualBox cannot start VMs"
      ISSUES=$((ISSUES + 1))
    fi
  else
    warn "VirtualBox installed but kernel modules not loaded"
    ISSUES=$((ISSUES + 1))
  fi
else
  theme_note "VirtualBox not installed — skipped"
fi

theme_section "Package noise"
if pkg_out="$(readiness_package_noise_list 2>/dev/null)"; then
  printf '%s\n' "${pkg_out}" | sed 's/^/  /'
  warn "Background package processes still running"
  ISSUES=$((ISSUES + 1))
else
  ok "No package background noise"
fi

echo
if (( ISSUES > 0 )); then
  theme_summary_box "Post-update summary" "Result: REVIEW" "Issues: ${ISSUES}" \
    "Next: ./system/system.sh daily-driver"
  exit 1
fi
theme_summary_box "Post-update summary" "Result: OK" "System stable after update"
exit 0
