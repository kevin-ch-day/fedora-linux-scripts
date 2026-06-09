#!/usr/bin/env bash
# system.sh — System maintenance launcher (host, maintenance, logs)
# Version: 0.1.8
#
# Run:
#   ./system/system.sh
#   ./run.sh --system
#   ./system/system.sh update
#   ./system/system.sh logs
#   ./system/system.sh --help

set -euo pipefail

SYSTEM_LAUNCHER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${SYSTEM_LAUNCHER_DIR}/.." && pwd)"

# shellcheck source=lib/menu.sh
source "${SYSTEM_LAUNCHER_DIR}/lib/menu.sh"

usage() {
  cat <<EOF
System maintenance — daily readiness, host snapshot, updates, logs, cleanup.

From main entry: ./run.sh → [1]  or  ./run.sh --system
Daily driver: ./run.sh --daily-driver-check · Disk summary: ./run.sh --disk-summary
Post-update: ./run.sh --post-update-check · Fedora doctor: ./run.sh --doctor (main menu [8])

Usage: $(basename "$0") [command|option]

Options:
  --help, -h     Show this help
  --menu         Interactive menu (default)

Commands:
  update         Full Fedora update (sudo; default --quick)
  info           Host snapshot
  monitor        Live dashboard
  backup         Export system state
  baseline       Fresh-install host baseline (report → logs/)
  rebuild-check  Pre-rebuild readiness (no installs)
  hardening-round1  OS hardening Round 1 (sudo, auto-detect host)
  hardening-round2  OS hardening Round 2 (strict firewall + services)
  firewall-strict   Custom strict zone — SSH only on wired
  listening-harden  MariaDB localhost · Avahi · LLMNR · BT/Wi-Fi
  security-audit    Read-only full security audit → logs/
  audit-summary     Fast live findings + action plan
  audit-plan        Ordered remediation plan from live findings
  host-context      Live host snapshot (users · network · posture)
  wired-only        Disable Bluetooth + Wi-Fi (wired Ethernet hosts)
  services-audit    Enabled/running services (Round 2 prep)
  doctor         Fedora doctor (same as ./run.sh --doctor)
  research-doctor Full research doctor (Android + MobSF — rebuild finale)
  logs           Open logs submenu

Workstation readiness (read-only by default):
  daily-driver       Daily driver check (boot · btrfs · LUKS · vbox · noise)
  btrfs-health       Btrfs device stats and scrub status (--scrub to start scrub)
  luks-readiness     LUKS keyslots and header backup presence
  virtualbox-readiness  VirtualBox modules and packages
  package-noise      PackageKit/dnf/flatpak background processes (--stop-session)
  post-update-check  Validate system after dnf upgrade

Toolkit root: ${FEDORA_ROOT}
EOF
}

if [[ $# -eq 0 ]]; then
  system_menu_init "${FEDORA_ROOT}"
  system_main_menu
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --menu)
      system_menu_init "${FEDORA_ROOT}"
      system_main_menu
      exit 0
      ;;
    update)
      shift
      if [[ $# -eq 0 ]]; then
        set -- --quick
      fi
      case "${1:-}" in
        --help|-h)
          exec bash "${SYSTEM_LAUNCHER_DIR}/system_update.sh" "$@"
          ;;
      esac
      exec sudo -E bash "${SYSTEM_LAUNCHER_DIR}/system_update.sh" "$@"
      ;;
    info)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/system_info.sh" "$@"
      ;;
    monitor)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/system_monitor.sh" "$@"
      ;;
    backup)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/backup_state.sh" "$@"
      ;;
    baseline)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/fresh_install_check.sh" "$@"
      ;;
    rebuild-check)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/rebuild_readiness_check.sh" "$@"
      ;;
    hardening-round1)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/hardening_round1.sh" "$@"
      ;;
    hardening-round2)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/hardening_round2.sh" "$@"
      ;;
    firewall-strict)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/hardening_firewall_strict.sh" "$@"
      ;;
    listening-harden)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/hardening_listening.sh" "$@"
      ;;
    security-audit)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/security_audit.sh" "$@"
      ;;
    audit-summary)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/security_audit.sh" --summary "$@"
      ;;
    audit-plan)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/security_audit.sh" --plan "$@"
      ;;
    host-context)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/host_context.sh" "$@"
      ;;
    wired-only)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/hardening_wired_only.sh" "$@"
      ;;
    services-audit)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/hardening_services_audit.sh" "$@"
      ;;
    doctor)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/research_doctor.sh" --android-only "$@"
      ;;
    research-doctor)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/research_doctor.sh" "$@"
      ;;
    logs)
      shift
      system_menu_init "${FEDORA_ROOT}"
      system_menu_logs
      exit 0
      ;;
    daily-driver)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/daily_driver_check.sh" "$@"
      ;;
    btrfs-health)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/btrfs_health.sh" "$@"
      ;;
    luks-readiness)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/luks_readiness.sh" "$@"
      ;;
    virtualbox-readiness)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/virtualbox_readiness.sh" "$@"
      ;;
    package-noise)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/package_noise.sh" "$@"
      ;;
    post-update-check)
      shift
      exec bash "${SYSTEM_LAUNCHER_DIR}/post_update_check.sh" "$@"
      ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
done
