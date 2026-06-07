#!/usr/bin/env bash
# lib/baseline.sh — fresh-install host baseline and rebuild readiness helpers
# Version: 0.1.1
#
# Source from system/fresh_install_check.sh and system/rebuild_readiness_check.sh.
# Checks are read-only by default. baseline_try_fix_dnf_repos() is an optional
# helper (passwordless sudo only) used by rebuild readiness and --check --fix-repos.

if [[ -n "${FEDORA_BASELINE_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_BASELINE_SH_LOADED=1

_BASELINE_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_BASELINE_LIB_DIR}/common.sh"
# shellcheck source=health.sh
source "${_BASELINE_LIB_DIR}/health.sh"
# shellcheck source=logging.sh
source "${_BASELINE_LIB_DIR}/logging.sh"
# shellcheck source=services.sh
source "${_BASELINE_LIB_DIR}/services.sh"

# ---------- report helpers ----------
baseline_section() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

baseline_run_cmd() {
  echo
  printf '$ %s\n' "$*"
  "$@" 2>&1 || echo "[exit ${?}]"
}

baseline_run_cmd_optional() {
  if have "$1"; then
    baseline_run_cmd "$@"
  else
    echo "(not installed: $1)"
  fi
}

# ---------- host facts ----------
baseline_is_uefi() {
  [[ -d /sys/firmware/efi ]]
}

baseline_uefi_label() {
  if baseline_is_uefi; then
    printf 'yes'
  else
    printf 'no'
  fi
}

baseline_fedora_release_line() {
  if [[ -r /etc/fedora-release ]]; then
    tr -d '\n' < /etc/fedora-release
  elif [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf '%s' "${PRETTY_NAME:-unknown}"
  else
    printf 'unknown'
  fi
}

baseline_is_fedora() {
  [[ -r /etc/fedora-release ]] && return 0
  [[ -r /etc/os-release ]] && grep -qi '^ID=fedora' /etc/os-release 2>/dev/null
}

baseline_nvidia_visible() {
  have lspci || return 1
  lspci 2>/dev/null | grep -qi nvidia
}

baseline_root_avail_mb() {
  df -Pm / 2>/dev/null | awk 'NR==2 {print $4}' || printf '0\n'
}

baseline_root_use_pct() {
  df -P / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5+0}' || printf '0\n'
}

baseline_home_use_pct() {
  df -P /home 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5+0}' || printf 'n/a\n'
}

baseline_ping_ok() {
  local host="$1"
  local tries="${2:-1}"
  have ping || return 1
  ping -c "${tries}" -W 3 "${host}" >/dev/null 2>&1
}

baseline_dnf_check_ok() {
  have dnf || return 1
  dnf check >/dev/null 2>&1 && return 0
  if baseline_sudo_available && [[ "${EUID}" -ne 0 ]]; then
    sudo dnf check >/dev/null 2>&1 && return 0
  fi
  return 1
}

# Repo files root-only (e.g. mode 600) break user-level dnf check.
baseline_unreadable_repo_files() {
  local f
  shopt -s nullglob
  for f in /etc/yum.repos.d/*.repo; do
    [[ -r "${f}" ]] || printf '%s\n' "${f}"
  done
  shopt -u nullglob
}

# Try fix when passwordless sudo is available (no prompt). Returns 0 if dnf check passes after.
baseline_try_fix_dnf_repos() {
  local root="${1:?toolkit root required}"
  local unreadable
  unreadable="$(baseline_unreadable_repo_files || true)"
  [[ -n "${unreadable}" ]] || return 1
  baseline_sudo_available || return 1
  sudo -n true 2>/dev/null || return 1
  info "Auto-fixing DNF repo permissions (passwordless sudo)..."
  sudo -n bash "${root}/system/fix_dnf_repo_permissions.sh" || return 1
  baseline_dnf_check_ok
}

baseline_sudo_available() {
  [[ "${EUID}" -eq 0 ]] && return 0
  have sudo
}

baseline_toolkit_lane_dirs_ok() {
  local root="${1:?toolkit root required}"
  local d
  for d in system dev android lib logs; do
    [[ -d "${root}/${d}" ]] || return 1
  done
  return 0
}

baseline_cmd_version() {
  local cmd="$1"
  shift
  if have "${cmd}"; then
    printf '%s: ' "${cmd}"
    "$cmd" "$@" 2>&1 | head -n 1
  else
    printf '%s: (not installed)\n' "${cmd}"
  fi
}

baseline_top_memory_processes() {
  local count="${1:-15}"
  echo "Top processes by memory:"
  ps -eo pid,comm,%mem,%cpu --sort=-%mem --no-headers 2>/dev/null | head -n "${count}" \
    | awk '{printf "  %-7s %-28s %6.1f %6.1f\n", $1, $2, $3, $4}' || echo "  (ps unavailable)"
}

# ---------- fresh install full collection ----------
baseline_collect_fresh_install() {
  local core_cmds=(
    git python3 pip3 gcc g++ make cmake java mysql curl wget unzip tar rsync htop btop tree vim nano
  )
  local cmd

  baseline_section "Identity"
  baseline_run_cmd_optional hostnamectl
  if [[ -r /etc/fedora-release ]]; then
    echo
    echo "/etc/fedora-release:"
    cat /etc/fedora-release
  fi
  baseline_run_cmd uname -a

  baseline_section "Firmware / boot"
  echo "UEFI detected (/sys/firmware/efi): $(baseline_uefi_label)"
  if mountpoint -q /boot/efi 2>/dev/null || grep -qs ' /boot/efi ' /proc/mounts 2>/dev/null; then
    echo "/boot/efi mount:"
    findmnt /boot/efi 2>/dev/null || df -hT /boot/efi 2>/dev/null || true
  else
    echo "/boot/efi: (not mounted or not present)"
  fi
  if have efibootmgr; then
    baseline_run_cmd efibootmgr
  else
    echo "efibootmgr: (not installed)"
  fi

  baseline_section "CPU"
  if have lscpu; then
    baseline_run_cmd lscpu
  else
    echo "Model: $(health_cpu_model)"
    echo "Threads: $(health_cpu_count)"
  fi

  baseline_section "Memory"
  if have free; then
    baseline_run_cmd free -h
  else
    echo "free: (not installed)"
  fi

  baseline_section "Storage layout"
  baseline_run_cmd_optional lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL
  baseline_run_cmd df -hT
  if baseline_sudo_available && have blkid; then
    baseline_run_cmd sudo blkid
  else
    echo "blkid: skipped (sudo or blkid unavailable)"
  fi

  baseline_section "GPU"
  if have lspci; then
    echo "lspci display adapters:"
    lspci 2>/dev/null | grep -iE 'vga|3d|display|nvidia' || echo "  (none matched)"
  else
    echo "lspci: (not installed)"
  fi
  echo "Loaded GPU-related modules:"
  if have lsmod; then
    lsmod 2>/dev/null | grep -iE 'nvidia|nouveau|amdgpu|radeon|i915' || echo "  (none matched)"
  else
    echo "  lsmod unavailable"
  fi
  if have nvidia-smi; then
    baseline_run_cmd nvidia-smi
  else
    echo "nvidia-smi: (not installed)"
  fi

  baseline_section "Network"
  if have ip; then
    baseline_run_cmd ip -br addr
  fi
  if have nmcli; then
    baseline_run_cmd nmcli device status
  else
    echo "nmcli: (not installed)"
  fi
  baseline_run_cmd_optional ping -c 1 -W 3 1.1.1.1
  baseline_run_cmd_optional ping -c 1 -W 3 fedoraproject.org

  baseline_section "Package manager"
  if have dnf; then
    baseline_run_cmd dnf check
    echo
    echo "dnf check-update (first 80 lines):"
    dnf check-update 2>&1 | head -n 80 || echo "[dnf check-update exit ${?}]"
  else
    echo "dnf: (not installed)"
  fi

  baseline_section "Core commands (presence)"
  for cmd in "${core_cmds[@]}"; do
    if have "${cmd}"; then
      printf '[OK]   %s\n' "${cmd}"
    else
      printf '[MISS] %s\n' "${cmd}"
    fi
  done

  baseline_section "Core command versions"
  baseline_cmd_version python3 --version
  baseline_cmd_version pip3 --version
  baseline_cmd_version git --version
  baseline_cmd_version gcc --version
  baseline_cmd_version g++ --version
  if have java; then
    echo -n "java: "
    java -version 2>&1 | head -n 1
  else
    echo "java: (not installed)"
  fi
  if have mysql; then
    baseline_cmd_version mysql --version
  else
    echo "mysql: (not installed)"
  fi

  baseline_section "Services (sshd · mariadb)"
  service_status_line sshd "sshd"
  service_status_line mariadb "mariadb"

  baseline_section "Uptime"
  baseline_run_cmd uptime

  baseline_section "Top memory processes"
  baseline_top_memory_processes 15

  baseline_section "Top CPU processes"
  health_top_processes 15
}

baseline_print_fresh_summary() {
  local ram_total="unknown"
  local swap_used="unknown"
  local root_pct home_pct nvidia_vis nvidia_smi

  if read -r _ ram_total _ _ < <(health_memory_summary 2>/dev/null || true); then
    : # ram_total set
  fi
  if read -r swap_used _ < <(health_swap_summary 2>/dev/null || true); then
    : # swap_used set
  fi

  root_pct="$(baseline_root_use_pct)"
  home_pct="$(baseline_home_use_pct)"
  if baseline_nvidia_visible; then
    nvidia_vis="yes"
  else
    nvidia_vis="no"
  fi
  if have nvidia-smi; then
    nvidia_smi="present"
  else
    nvidia_smi="absent"
  fi

  baseline_section "Summary"
  echo "  Hostname:           $(health_hostname)"
  echo "  Fedora release:     $(baseline_fedora_release_line)"
  echo "  UEFI:               $(baseline_uefi_label)"
  echo "  CPU threads:        $(health_cpu_count)"
  echo "  RAM total:          ${ram_total}"
  echo "  Swap used:          ${swap_used}"
  echo "  Root filesystem:    ${root_pct}% used"
  echo "  Home filesystem:    ${home_pct}% used"
  echo "  NVIDIA visible:     ${nvidia_vis}"
  echo "  nvidia-smi:         ${nvidia_smi}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
