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
INSTALL_PODMAN=1
INSTALL_KVM=1

resolve_docker_package() {
  package_available() {
    dnf -q list --available "$1" >/dev/null 2>&1
  }
  if pkg_present docker docker; then
    printf 'docker\n'
    return 0
  fi
  if package_available moby-engine; then
    printf 'moby-engine\n'
    return 0
  fi
  if package_available docker; then
    printf 'docker\n'
    return 0
  fi
  printf '\n'
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Installs git/curl/unzip, Podman, Docker, QEMU/KVM, libvirt,
and virt-manager. Enables docker/libvirtd when the packages exist and adds
$(real_user) to docker and libvirt groups.

Options:
  --help, -h     Show this help
  --no-docker    Skip docker package, service, and group
  --podman-only  Install Podman engine only
  --docker-only  Install Docker engine only
  --kvm-only     Install KVM/libvirt only

Run with sudo.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --no-docker) INSTALL_DOCKER=0; shift ;;
    --podman-only)
      INSTALL_PODMAN=1
      INSTALL_DOCKER=0
      INSTALL_KVM=0
      shift
      ;;
    --docker-only)
      INSTALL_PODMAN=0
      INSTALL_DOCKER=1
      INSTALL_KVM=0
      shift
      ;;
    --kvm-only)
      INSTALL_PODMAN=0
      INSTALL_DOCKER=0
      INSTALL_KVM=1
      shift
      ;;
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

if (( INSTALL_PODMAN || INSTALL_DOCKER )); then
  info "Installing containers..."
  if (( INSTALL_PODMAN )); then
    pkg_install_optional podman
  else
    info "Skipping podman"
  fi
  if (( INSTALL_DOCKER )); then
    DOCKER_PKG="$(resolve_docker_package)"
    if [[ -n "${DOCKER_PKG}" ]]; then
      pkg_install_optional "${DOCKER_PKG}"
    else
      warn "No Docker-compatible engine package available in enabled repos"
    fi
    if cmd_available docker && have systemctl; then
      service_enable_now docker
      user_add_supplementary_group "${INVOKER}" docker
    else
      warn "docker not available — skipped service enable and group add"
    fi
  else
    info "Skipping docker"
  fi
  echo
fi

if (( INSTALL_KVM )); then
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
fi

ok "Fedora infra stack setup complete!"
echo "[NOTE] Log out/in if you were added to docker or libvirt groups."
echo "[CHECK] podman info | docker info | virsh list --all"
