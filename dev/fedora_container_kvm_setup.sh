#!/usr/bin/env bash
# fedora_container_kvm_setup.sh — Fedora baseline infra stack (containers + virtualization + core utils)
# Version: 0.3.0
#
# Installs:
# - common utilities: git, curl, unzip
# - containers: podman (+ optional docker)
# - virtualization: qemu-kvm, libvirt, virt-manager
#
# Run:
#   sudo ./dev/fedora_container_kvm_setup.sh
#   sudo ./dev/fedora_container_kvm_setup.sh --no-docker

set -euo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/packages.sh
source "${_SCRIPT_DIR}/../lib/packages.sh"
# shellcheck source=../lib/services.sh
source "${_SCRIPT_DIR}/../lib/services.sh"

INSTALL_DOCKER=1

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Installs git/curl/unzip, podman, docker (optional), QEMU/KVM, libvirt,
and virt-manager. Enables docker/libvirtd when the packages exist and adds
$(real_user) to docker and libvirt groups.

Options:
  --help, -h     Show this help
  --no-docker    Skip docker package, service, and group

Run with sudo.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --no-docker) INSTALL_DOCKER=0; shift ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
done

require_root "Run with sudo: sudo ./dev/fedora_container_kvm_setup.sh"

INVOKER="$(real_user)"
info "Fedora infra stack setup (containers + virtualization + core utils)"
info "Invoker user: ${INVOKER}"
echo

info "Installing common utilities..."
pkg_install_optional git
pkg_install_optional curl
pkg_install_optional unzip
echo

info "Installing containers..."
pkg_install_optional podman
if (( INSTALL_DOCKER )); then
  pkg_install_optional docker
  if have docker && have systemctl; then
    service_enable_now docker
    user_add_supplementary_group "${INVOKER}" docker
  else
    warn "docker not available — skipped service enable and group add"
  fi
else
  info "Skipping docker (--no-docker)"
fi
echo

info "Installing virtualization (KVM/QEMU)..."
pkg_install_optional qemu-kvm
pkg_install_optional libvirt
pkg_install_optional libvirt-daemon-kvm
pkg_install_optional virt-manager
if have systemctl; then
  service_enable_now libvirtd
fi
if getent group libvirt >/dev/null 2>&1; then
  user_add_supplementary_group "${INVOKER}" libvirt
else
  warn "libvirt group not found — skipped group add"
fi
echo

ok "Fedora infra stack setup complete!"
echo "[NOTE] Log out/in if you were added to docker or libvirt groups."
echo "[CHECK] podman info | docker info | virsh list --all"
