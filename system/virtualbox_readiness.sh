#!/usr/bin/env bash
# virtualbox_readiness.sh — VirtualBox host readiness (read-only)
# Version: 0.1.1
#
# Run:
#   ./system/virtualbox_readiness.sh
#   ./system/system.sh virtualbox-readiness

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

Read-only VirtualBox host readiness: kernel, modules, vboxdrv, packages.

Also: ./system/system.sh virtualbox-readiness
      sudo ./dev/virtualbox_setup.sh  (install/repair)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

ISSUES=0
running="$(uname -r)"

theme_report_header "VirtualBox readiness" \
  "Kernel: ${running}" \
  "Read-only host module check"

theme_section "Kernel"
if readiness_vbox_kernel_matches_running; then
  ok "Running kernel matches latest installed RPM kernel"
else
  warn "Older kernel booted — vboxdrv often fails until you reboot into the newest kernel"
  ISSUES=$((ISSUES + 1))
fi

theme_section "Kernel modules"
mods="$(readiness_vbox_modules_loaded)"
if [[ -n "${mods}" ]]; then
  printf '%s\n' "${mods}"
  echo "${mods}" | grep -q vboxdrv && ok "vboxdrv loaded" || warn "vboxdrv not in lsmod output"
else
  warn "No vbox modules loaded (vboxdrv · vboxnetflt · vboxnetadp)"
  ISSUES=$((ISSUES + 1))
fi

theme_section "vboxdrv service"
if have systemctl; then
  systemctl status vboxdrv --no-pager 2>/dev/null | head -n 8 || warn "vboxdrv unit not active"
else
  theme_note "systemctl not available"
fi

theme_section "VBoxManage"
if readiness_vbox_is_installed; then
  if vbox_ver="$(readiness_vbox_version 2>/dev/null)"; then
    ok "VBoxManage: ${vbox_ver}"
  else
    warn "VBoxManage version unreadable — check /dev/vboxdrv and vboxdrv.service"
    ISSUES=$((ISSUES + 1))
  fi
  if [[ -n "${mods}" ]] && ! readiness_vbox_char_dev_ready; then
    warn "/dev/vboxdrv missing (modules in lsmod but char device absent)"
    ISSUES=$((ISSUES + 1))
  fi
else
  warn "VirtualBox package not installed"
  ISSUES=$((ISSUES + 1))
fi

theme_section "Packages"
if readiness_vbox_is_installed; then
  pkg_out="$(readiness_vbox_packages_status)"
  if [[ -n "${pkg_out}" ]]; then
    printf '%s\n' "${pkg_out}"
  else
    warn "VirtualBox RPM query returned no package lines"
    ISSUES=$((ISSUES + 1))
  fi
else
  theme_note "Skipped — VirtualBox not installed"
fi

echo
if (( ISSUES > 0 )); then
  theme_summary_box "VirtualBox summary" "Result: REVIEW" "Issues: ${ISSUES}" \
    "Fix: sudo ./dev/virtualbox_setup.sh" \
    "Tip: reboot into newest kernel if vboxdrv failed after update"
  exit 1
fi
theme_summary_box "VirtualBox summary" "Result: OK" "Modules and VBoxManage available"
exit 0
