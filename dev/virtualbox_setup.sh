#!/usr/bin/env bash
# virtualbox_setup.sh — Install VirtualBox host packages from RPM Fusion Free
# Version: 0.1.0
#
# Run:
#   sudo ./dev/virtualbox_setup.sh
#   sudo ./dev/virtualbox_setup.sh --help

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/packages.sh
source "${_SCRIPT_DIR}/../lib/packages.sh"

FEDORA_RELEASE="$(rpm -E %fedora)"
RPMFUSION_FREE_RELEASE_PKG="rpmfusion-free-release-${FEDORA_RELEASE}"
RPMFUSION_FREE_RELEASE_URL="https://download1.rpmfusion.org/free/fedora/${RPMFUSION_FREE_RELEASE_PKG}.noarch.rpm"
INVOKER="$(real_user)"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Install VirtualBox host packages from RPM Fusion Free on Fedora.
This installs the RPM Fusion Free release package when needed, then installs
VirtualBox, akmod-VirtualBox, kernel development headers, and build helpers.

Options:
  --help, -h     Show this help

Run with sudo.
EOF
}

rpmfusion_free_enabled() {
  dnf repolist enabled 2>/dev/null \
    | awk '{print $1}' \
    | grep -Eq '^rpmfusion-free($|-updates$)'
}

ensure_rpmfusion_free() {
  if rpmfusion_free_enabled || rpm -q "${RPMFUSION_FREE_RELEASE_PKG}" >/dev/null 2>&1; then
    ok "RPM Fusion Free already configured"
    return 0
  fi

  info "Installing RPM Fusion Free release package for Fedora ${FEDORA_RELEASE}..."
  pkg_dnf_run "Failed to install RPM Fusion Free release package" install "${RPMFUSION_FREE_RELEASE_URL}"

  if ! rpmfusion_free_enabled && ! rpm -q "${RPMFUSION_FREE_RELEASE_PKG}" >/dev/null 2>&1; then
    die "RPM Fusion Free still not available after install"
  fi
  ok "RPM Fusion Free configured"
}

ensure_running_kernel_devel() {
  local running_kernel
  running_kernel="$(uname -r)"

  if rpm -q "kernel-devel-${running_kernel}" >/dev/null 2>&1; then
    ok "kernel-devel matches running kernel: ${running_kernel}"
    return 0
  fi

  if dnf -q list --available "kernel-devel-${running_kernel}" >/dev/null 2>&1; then
    info "Installing kernel-devel for running kernel ${running_kernel}..."
    pkg_dnf_run "Failed to install kernel-devel for ${running_kernel}" install "kernel-devel-${running_kernel}"
    ok "Installed kernel-devel for running kernel ${running_kernel}"
    return 0
  fi

  warn "kernel-devel-${running_kernel} not available in enabled repos"
  info "Installing latest kernel-devel instead..."
  pkg_install_rpm_if_missing kernel-devel
  warn "Reboot into the newest kernel before using VirtualBox if module build fails for ${running_kernel}"
}

secure_boot_note() {
  if cmd_available mokutil; then
    case "$(mokutil --sb-state 2>/dev/null || true)" in
      *enabled*)
        warn "Secure Boot is enabled. Unsigned VirtualBox kernel modules may be blocked."
        warn "You may need to enroll a Machine Owner Key or disable Secure Boot."
        ;;
    esac
  fi
}

report_virtualbox() {
  local vboxmanage_path vbox_ver
  if vboxmanage_path="$(cmd_binary_path VBoxManage 2>/dev/null)"; then
    vbox_ver="$("${vboxmanage_path}" --version 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | tail -n 1 || echo unknown)"
    ok "VBoxManage: ${vboxmanage_path} (${vbox_ver})"
  else
    warn "VBoxManage not found on PATH after install"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
done

require_root "Run with sudo: sudo ./dev/virtualbox_setup.sh"

info "VirtualBox host setup (RPM Fusion Free)"
info "Fedora release: ${FEDORA_RELEASE}"
info "Invoker user: ${INVOKER}"
echo

ensure_rpmfusion_free
echo

info "Installing build prerequisites for VirtualBox kernel modules..."
pkg_install_rpm_if_missing akmods
pkg_install_rpm_if_missing gcc
pkg_install_rpm_if_missing make
pkg_install_rpm_if_missing elfutils-libelf-devel
ensure_running_kernel_devel
echo

info "Installing VirtualBox host packages..."
pkg_install_rpm_if_missing VirtualBox
pkg_install_rpm_if_missing akmod-VirtualBox
echo

if getent group vboxusers >/dev/null 2>&1; then
  user_add_supplementary_group "${INVOKER}" vboxusers
else
  warn "vboxusers group not found after package install"
fi

if cmd_available akmods; then
  info "Attempting to build the VirtualBox kernel module for $(uname -r)..."
  if akmods --force --kernels "$(uname -r)" --akmod VirtualBox; then
    ok "akmods completed for VirtualBox"
  else
    warn "akmods did not complete cleanly for $(uname -r)"
    warn "Reboot into the latest kernel, then rerun this script if needed"
  fi
fi

if cmd_available modprobe; then
  if modprobe vboxdrv 2>/dev/null; then
    ok "Loaded vboxdrv kernel module"
  else
    warn "Could not load vboxdrv right now"
  fi
fi

secure_boot_note
report_virtualbox

echo
theme_result_ready "VirtualBox setup complete"
theme_note "Log out/in if the vboxusers group was added"
theme_note "Launch: VirtualBox · verify: VBoxManage --version"
