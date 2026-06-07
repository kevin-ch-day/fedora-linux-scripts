#!/usr/bin/env bash
# lib/health.sh — host health, visibility, and diagnostic snapshot helpers
# Version: 0.2.2
#
# Source from task scripts:
#   _dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck source=../lib/health.sh
#   source "${_dir}/../lib/health.sh"
#
# Do not execute directly.

if [[ -n "${FEDORA_HEALTH_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_HEALTH_SH_LOADED=1

_HEALTH_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_HEALTH_LIB_DIR}/common.sh"

# ---------- display / thresholds ----------
human_pct_color() {
  local pct="$1"
  if awk "BEGIN{exit !(${pct} >= 80)}"; then
    printf '%s' "${RED}"
  elif awk "BEGIN{exit !(${pct} >= 60)}"; then
    printf '%s' "${YELLOW}"
  else
    printf '%s' "${GREEN}"
  fi
}

# ---------- system identity ----------
health_hostname() {
  hostname
}

health_os_pretty() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf '%s\n' "${PRETTY_NAME:-unknown}"
  else
    printf 'unknown\n'
  fi
}

health_kernel() {
  uname -r
}

health_uptime() {
  uptime -p 2>/dev/null || printf 'unknown\n'
}

health_timezone() {
  timedatectl show -p Timezone --value 2>/dev/null || printf 'unknown\n'
}

health_package_count() {
  rpm -qa 2>/dev/null | wc -l | tr -d ' '
}

health_python_version() {
  python3 --version 2>/dev/null || printf 'not installed\n'
}

# ---------- CPU ----------
health_cpu_model() {
  local model="unknown"
  if have lscpu; then
    if lscpu -J >/dev/null 2>&1; then
      model="$(lscpu -J | awk -F\" '/"Model name"/ {print $4; exit}' || echo "unknown")"
    else
      model="$(lscpu | awk -F: '/Model name/ {sub(/^[ \t]+/, "", $2); print $2; exit}' || echo "unknown")"
    fi
  fi
  printf '%s\n' "${model}"
}

health_cpu_count() {
  nproc --all 2>/dev/null || printf 'unknown\n'
}

# Prints: sockets cores_per_socket threads_per_core (space-separated)
health_cpu_topology() {
  local sockets="unknown"
  local cores_per_socket="unknown"
  local threads_per_core="unknown"

  if have lscpu; then
    if lscpu -J >/dev/null 2>&1; then
      sockets="$(lscpu -J | awk -F\" '/"Socket\\(s\\)"/ {print $4; exit}' || echo "unknown")"
      cores_per_socket="$(lscpu -J | awk -F\" '/"Core\\(s\\) per socket"/ {print $4; exit}' || echo "unknown")"
      threads_per_core="$(lscpu -J | awk -F\" '/"Thread\\(s\\) per core"/ {print $4; exit}' || echo "unknown")"
    else
      sockets="$(lscpu | awk -F: '/Socket\\(s\\)/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' || echo "unknown")"
      cores_per_socket="$(lscpu | awk -F: '/Core\\(s\\) per socket/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' || echo "unknown")"
      threads_per_core="$(lscpu | awk -F: '/Thread\\(s\\) per core/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' || echo "unknown")"
    fi
  fi

  printf '%s %s %s\n' "${sockets}" "${cores_per_socket}" "${threads_per_core}"
}

health_loadavg() {
  awk '{print $1", "$2", "$3}' /proc/loadavg 2>/dev/null || printf 'unknown\n'
}

# Prints CPU usage percent (e.g. 16.69) or nothing if unavailable.
health_cpu_usage_pct() {
  if ! have mpstat; then
    return 1
  fi
  local usage
  usage="$(mpstat 1 1 | awk '$1=="Average:" && $2=="all" {idle=$NF; printf "%.2f", (100-idle)}' || true)"
  [[ -n "${usage}" ]] || return 1
  printf '%s\n' "${usage}"
}

# ---------- memory ----------
# Prints: used_h total_h pct avail_h (space-separated) on stdout.
health_memory_summary() {
  have free || return 1

  local total used avail pct
  local total_h used_h avail_h

  read -r total used _ _ _ avail < <(free -b | awk 'NR==2 {print $2,$3,$4,$5,$6,$7}')
  pct="$(awk -v u="$used" -v t="$total" 'BEGIN{printf "%.2f", (u/t)*100}')"

  if have numfmt; then
    total_h="$(numfmt --to=iec --suffix=B "$total")"
    used_h="$(numfmt --to=iec --suffix=B "$used")"
    avail_h="$(numfmt --to=iec --suffix=B "$avail")"
  else
    total_h="$(free -h | awk 'NR==2{print $2}')"
    used_h="$(free -h | awk 'NR==2{print $3}')"
    avail_h="$(free -h | awk 'NR==2{print $7}')"
  fi

  printf '%s %s %s %s\n' "${used_h}" "${total_h}" "${pct}" "${avail_h}"
}

# Prints: used_mib total_mib avail_mib pct buffcache_mib (for live monitor)
health_mem_stats_monitor() {
  awk '
    /^MemTotal:/ {t=$2}
    /^MemAvailable:/ {a=$2}
    /^Buffers:/ {b=$2}
    /^Cached:/ {c=$2}
    END{
      if (t==0) {print "0 0 0 0 0"; exit}
      used=t-a; pct=(used/t)*100; bc=b+c;
      printf "%d %d %d %.0f %d", used/1024, t/1024, a/1024, pct, bc/1024
    }' /proc/meminfo 2>/dev/null || printf '0 0 0 0 0\n'
}

# Prints: used_mib total_mib pct (for live monitor swap line)
health_swap_stats_monitor() {
  awk '
    /^SwapTotal:/{t=$2}
    /^SwapFree:/ {f=$2}
    END{
      used=t-f; pct=(t>0)?(used/t)*100:0;
      printf "%d %d %.0f", used/1024, t/1024, pct
    }' /proc/meminfo 2>/dev/null || printf '0 0 0\n'
}

# Prints: swap_used_h swap_total_h (space-separated)
health_swap_summary() {
  have free || return 1

  local swap_total swap_used
  local swap_total_h swap_used_h

  read -r swap_total swap_used _ < <(free -b | awk 'NR==3 {print $2,$3,$4}')

  if have numfmt; then
    swap_total_h="$(numfmt --to=iec --suffix=B "$swap_total")"
    swap_used_h="$(numfmt --to=iec --suffix=B "$swap_used")"
  else
    swap_total_h="$(free -h | awk 'NR==3{print $2}')"
    swap_used_h="$(free -h | awk 'NR==3{print $3}')"
  fi

  printf '%s %s\n' "${swap_used_h}" "${swap_total_h}"
}

# ---------- disk ----------
health_root_disk_usage() {
  df -h / | sed '1d' | awk '{print "   - /: " $3 " used of " $2 " (" $5 ")"}' || true
}

health_disk_mount_summary() {
  local mount="$1"
  have df || return 1
  if df -hT "${mount}" >/dev/null 2>&1; then
    df -hT "${mount}" | awk 'NR==2 {printf " %-10s: %s used of %s (%s) [%s]\n", "'"${mount}"'", $4, $3, $6, $2}'
  fi
}

health_disk_top_mounts() {
  have df || return 1
  df -hT | awk 'NR==1{next} $2 !~ /(tmpfs|devtmpfs)/ {print $0}' \
    | awk '{gsub(/%/,"",$6); printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n",$7,$2,$3,$4,$5,$6,$1}' \
    | sort -k6,6nr | head -n 5 \
    | awk '{printf "  - %-12s %-8s %6s/%-6s (%s%%)\n",$1,$2,$4,$3,$6}'
}

# Root filesystem use percent (integer, for live monitors)
health_root_disk_pct() {
  df -P / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5+0}' || printf '0\n'
}

# ---------- network ----------
health_default_route() {
  ip route show default 2>/dev/null | head -n 1 || true
}

health_ipv4_interfaces() {
  have ip || return 1
  ip -o -4 addr show 2>/dev/null | awk '{printf "  - %-10s %s\n", $2, $4}' || true
}

# ---------- systemd ----------
health_failed_systemd_units_count() {
  if ! have systemctl; then
    printf '0\n'
    return 0
  fi
  systemctl --failed --no-legend 2>/dev/null | wc -l | tr -d ' '
}

health_failed_systemd_units_list() {
  have systemctl || return 0
  systemctl --failed --no-legend 2>/dev/null || true
}

# ---------- snapshots ----------
health_post_update_snapshot() {
  echo
  echo "Quick health snapshot:"
  echo "  Disk usage:"
  health_root_disk_usage

  if have systemctl; then
    local failed
    failed="$(health_failed_systemd_units_count)"
    echo "  Failed systemd units: ${failed}"
    if [[ "${failed}" != "0" ]]; then
      health_failed_systemd_units_list
    fi
  fi
}

health_quick_snapshot() {
  health_post_update_snapshot
}

health_top_processes() {
  local count="${1:-15}"
  echo "Top processes by CPU:"
  ps -eo pid,comm,%cpu,%mem --sort=-%cpu --no-headers | head -n "${count}" \
    | awk '{printf "  %-7s %-28s %6.1f %6.1f\n", $1, $2, $3, $4}'
}

# Full host snapshot (used by system_info.sh and system lane menu)
health_print_system_info() {
  local cpu_sockets cpu_cores cpu_threads usage color default_route

  _health_info_hline() { echo "${CYAN}=====================================================${RESET}"; }
  _health_info_box_title() { echo "${CYAN}┌──────────────── $1 ─────────────────┐${RESET}"; }
  _health_info_box_end() { echo "${CYAN}└──────────────────────────────────────────┘${RESET}"; }
  _health_info_kv() { printf " %-10s: %s\n" "$1" "$2"; }
  _health_info_effective_user() { id -un; }

  _health_info_hline
  echo "   Fedora System Information"
  echo "   $(date -Is)"
  _health_info_hline

  echo
  _health_info_box_title "SYSTEM"
  _health_info_kv "Hostname" "$(health_hostname)"
  _health_info_kv "OS" "$(health_os_pretty)"
  _health_info_kv "Kernel" "$(health_kernel)"
  _health_info_kv "Uptime" "$(health_uptime)"
  _health_info_kv "Timezone" "$(health_timezone)"
  _health_info_kv "Packages" "$(health_package_count) installed"
  _health_info_kv "Python" "$(health_python_version)"
  _health_info_kv "Invoker" "$(real_user)"
  _health_info_kv "Effective" "$(_health_info_effective_user) (uid=$(id -u))"
  _health_info_box_end

  echo
  _health_info_box_title "CPU"
  read -r cpu_sockets cpu_cores cpu_threads < <(health_cpu_topology)
  _health_info_kv "Model" "$(health_cpu_model)"
  _health_info_kv "CPUs" "$(health_cpu_count)"
  _health_info_kv "Sockets" "${cpu_sockets}"
  _health_info_kv "Cores/sock" "${cpu_cores}"
  _health_info_kv "Thr/core" "${cpu_threads}"
  _health_info_kv "Load Avg" "$(health_loadavg)"
  if have mpstat; then
    if usage="$(health_cpu_usage_pct 2>/dev/null || true)" && [[ -n "${usage}" ]]; then
      color="$(human_pct_color "${usage}")"
      _health_info_kv "Usage" "${color}${usage}%${RESET}"
    else
      _health_info_kv "Usage" "unknown"
    fi
  else
    _health_info_kv "Usage" "install sysstat for mpstat"
  fi
  _health_info_box_end

  echo
  _health_info_box_title "RAM"
  if read -r mem_used mem_total mem_pct mem_avail < <(health_memory_summary); then
    color="$(human_pct_color "${mem_pct}")"
    _health_info_kv "Memory" "${mem_used} / ${mem_total} (${color}${mem_pct}%${RESET}), Avail ${mem_avail}"
    if read -r swap_used swap_total < <(health_swap_summary); then
      _health_info_kv "Swap" "${swap_used} used / ${swap_total} total"
    fi
  else
    _health_info_kv "RAM" "free not installed"
  fi
  _health_info_box_end

  echo
  _health_info_box_title "DISK"
  if have df; then
    health_disk_mount_summary "/"
    health_disk_mount_summary "/home"
    health_disk_mount_summary "/boot"
    health_disk_mount_summary "/boot/efi"
    echo " Mounts (top):"
    health_disk_top_mounts
  else
    _health_info_kv "Disk" "df not installed"
  fi
  _health_info_box_end

  echo
  _health_info_box_title "NETWORK"
  if have ip; then
    default_route="$(health_default_route)"
    _health_info_kv "Default" "${default_route:-none}"
    echo " Interfaces (IPv4):"
    health_ipv4_interfaces
  else
    _health_info_kv "Network" "ip not installed"
  fi
  _health_info_box_end

  echo
  echo "${GREEN}Done.${RESET}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
