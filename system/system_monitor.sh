#!/usr/bin/env bash
# system_monitor.sh — Live system dashboard (CPU, RAM, disk, network, PSI)
# Version: 0.2.0
#
# Run:
#   ./system/system_monitor.sh
#   ./system/system_monitor.sh --interval 5
#   ./system/system_monitor.sh --help

set -euo pipefail

INTERVAL=7

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      cat <<EOF
Usage: $(basename "$0") [--interval SECONDS] [--help]

Live terminal dashboard. Blocks until Ctrl+C.

Options:
  --interval, -i SEC   Refresh interval (default: 7)
  --help, -h           Show this help
EOF
      exit 0
      ;;
    --interval|-i)
      INTERVAL="${2:?missing seconds}"
      shift 2
      ;;
    *)
      echo "[ERROR] Unknown option: $1 (try --help)" >&2
      exit 2
      ;;
  esac
done

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/health.sh
source "${_SCRIPT_DIR}/../lib/health.sh"
theme_set_lane system

_mon_cols() { tput cols 2>/dev/null || echo 100; }
_mon_hr() { theme_rule '─' "$(_mon_cols)"; }
_mon_safe() { "$@" 2>/dev/null || true; }

# ---- bars ----
bar() {
  theme_gauge_bar "$@"
}

# ---- metrics ----
cpu_total() {
  local pct
  if pct="$(health_cpu_usage_pct 2>/dev/null)"; then
    awk -v p="${pct}" 'BEGIN{printf "%.0f", p+0}'
    return 0
  fi
  if command -v mpstat >/dev/null 2>&1; then
    _mon_safe mpstat 1 1 | awk '/Average:/ && $3=="all"{printf "%.0f", 100-$12}' || echo 0
  else
    local a b
    read -r a < <(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5}' /proc/stat)
    sleep 0.2
    read -r b < <(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5}' /proc/stat)
    awk -v a="$a" -v b="$b" 'BEGIN{
      split(a,A," "); split(b,B," ");
      dt=B[1]-A[1]; di=B[2]-A[2];
      if (dt<=0) {print 0; exit}
      printf "%.0f", (1 - (di/dt))*100
    }'
  fi
}

load_line() {
  health_loadavg 2>/dev/null | tr ',' ' ' || awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null || echo "0 0 0"
}

uptime_pretty() {
  _mon_safe awk '{
    up=$1;
    d=int(up/86400); up%=86400;
    h=int(up/3600);  up%=3600;
    m=int(up/60);
    if (d>0) printf "%dd %dh %dm", d,h,m; else printf "%dh %dm", h,m;
  }' /proc/uptime || echo "-"
}

mem_stats() {
  health_mem_stats_monitor
}

swap_stats() {
  health_swap_stats_monitor
}

# ---- PSI one-line (avg10) ----
psi_avg10() {
  if [[ -r /proc/pressure/cpu ]]; then
    local cpu mem io
    cpu="$(awk 'match($0,/avg10=([0-9.]+)/,m){print m[1]; exit}' /proc/pressure/cpu 2>/dev/null || echo 0)"
    mem="$(awk 'match($0,/avg10=([0-9.]+)/,m){print m[1]; exit}' /proc/pressure/memory 2>/dev/null || echo 0)"
    io="$(awk  'match($0,/avg10=([0-9.]+)/,m){print m[1]; exit}' /proc/pressure/io 2>/dev/null || echo 0)"
    printf "%s %s %s" "${cpu:-0}" "${mem:-0}" "${io:-0}"
  else
    printf "0 0 0"
  fi
}

# ---- disk usage ----
root_disk_pct() { health_root_disk_pct; }

disk_table() {
  if theme_use_color; then
    printf '%sDisk%s\n' "${THEME_BOLD}${THEME_FG}" "${THEME_RESET}"
  else
    echo "Disk"
  fi
  if command -v df >/dev/null 2>&1; then
    printf "  %-14s %-6s %-6s %-6s %-5s %s\n" "MOUNT" "TYPE" "SIZE" "USED" "USE%" "DEVICE"
    _mon_safe df -hT -x tmpfs -x devtmpfs | awk '
      NR==1{next}
      $7=="/" || $7=="/home" || $7=="/boot" || $7=="/boot/efi" {
        gsub("%","",$6);
        printf "  %-14.14s %-6s %-6s %-6s %-5s %s\n",$7,$2,$3,$4,$6"%",$1
      }'
  else
    if theme_use_color; then
      printf '  %sdf not found%s\n' "${THEME_MUTED}" "${THEME_RESET}"
    else
      echo "  df not found"
    fi
  fi
  _mon_hr
}

# ---- network ----
primary_iface() {
  local i
  i="$(ip -o route show default 2>/dev/null | awk '{for (n=1;n<=NF;n++) if ($n=="dev") {print $(n+1); exit}}' || true)"
  [[ -n "${i:-}" ]] && { echo "$i"; return; }
  ip -o link show 2>/dev/null | awk -F': ' '$2!="lo"{print $2; exit}' || true
}

human_rate() {
  local bps="${1:-0}"
  if (( bps >= 1024*1024 )); then
    awk -v b="$bps" 'BEGIN{printf "%.2f MiB/s", b/1048576}'
  elif (( bps >= 1024 )); then
    awk -v b="$bps" 'BEGIN{printf "%.1f KiB/s", b/1024}'
  else
    printf "%d B/s" "$bps"
  fi
}

net_rate_line() {
  local iface="${1:-}"
  [[ -z "$iface" ]] && { echo "n/a"; return; }

  local rx1 tx1 rx2 tx2
  rx1="$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)"
  tx1="$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)"
  sleep 1
  rx2="$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)"
  tx2="$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)"
  local rxps=$(( rx2-rx1 ))
  local txps=$(( tx2-tx1 ))

  printf "%s RX:%s  TX:%s" "$iface" "$(human_rate "$rxps")" "$(human_rate "$txps")"
}

conn_counts() {
  local tcp udp
  tcp="$(_mon_safe ss -tan | awk 'NR>1{c++} END{print c+0}')"
  udp="$(_mon_safe ss -uan | awk 'NR>1{c++} END{print c+0}')"
  printf "TCP:%s UDP:%s" "${tcp:-0}" "${udp:-0}"
}

# ---- disk IO rate ----
pick_disk() {
  local src pk
  src="$(df -P / 2>/dev/null | awk 'NR==2{print $1}' || true)"
  [[ -z "${src:-}" ]] && { echo ""; return; }
  if command -v lsblk >/dev/null 2>&1; then
    pk="$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1 || true)"
    [[ -n "${pk:-}" ]] && { echo "$pk"; return; }
    pk="$(lsblk -no NAME "$src" 2>/dev/null | head -n1 || true)"
    [[ -n "${pk:-}" ]] && { echo "$pk"; return; }
  fi
  echo ""
}

disk_io_rate() {
  local d="${1:-}"
  [[ -z "$d" ]] && { echo "n/a"; return; }

  local a b
  a="$(awk -v d="$d" '$3==d{print $6,$10}' /proc/diskstats 2>/dev/null || echo "0 0")"
  sleep 1
  b="$(awk -v d="$d" '$3==d{print $6,$10}' /proc/diskstats 2>/dev/null || echo "0 0")"

  local ar aw br bw
  read -r ar aw <<<"$a"
  read -r br bw <<<"$b"

  local rsec=$(( br-ar ))
  local wsec=$(( bw-aw ))
  local rkb=$(( (rsec*512)/1024 ))
  local wkb=$(( (wsec*512)/1024 ))
  printf "R:%sKiB/s W:%sKiB/s" "$rkb" "$wkb"
}

# ---- temps (Fahrenheit) ----
temps_line() {
  if command -v sensors >/dev/null 2>&1; then
    local c
    c="$(
      sensors 2>/dev/null | awk '
        /Package id 0:|Tctl:|Tdie:|CPU Temperature:|Core 0:/ {
          if (match($0, /\+([0-9.]+)°?C/, m)) { print m[1]; exit }
        }
      '
    )"
    if [[ -z "${c:-}" ]]; then
      c="$(
        sensors 2>/dev/null | awk 'match($0, /\+([0-9.]+)°?C/, m) { print m[1]; exit }'
      )"
    fi
    if [[ -n "${c:-}" ]]; then
      awk -v c="$c" 'BEGIN{printf "%.1f°F", (c*9/5)+32}'
    else
      printf "n/a"
    fi
  else
    printf "n/a"
  fi
}

# ---- Spotlight ----
TOP_KW_REGEX='python|java|adb|frida|tcpdump|wireshark|mitm|chrome|qemu|emulator|node|postgres|mariadbd|mysqld'

spotlight() {
  if theme_use_color; then
    printf '%sSpotlight%s  %s(%s)%s\n' \
      "${THEME_BOLD}${THEME_FG}" "${THEME_RESET}" \
      "${THEME_MUTED}" "${TOP_KW_REGEX}" "${THEME_RESET}"
  else
    printf 'Spotlight  (%s)\n' "${TOP_KW_REGEX}"
  fi
  printf "  %-7s %-24s %7s %7s\n" "PID" "COMMAND" "%CPU" "%MEM"

  _mon_safe ps -eo pid,comm,%cpu,%mem --sort=-%cpu --no-headers | \
    awk -v r="$TOP_KW_REGEX" '$2 ~ r {printf "  %-7s %-24.24s %7.1f %7.1f\n",$1,$2,$3,$4}' | \
    head -n 8

  _mon_hr
}

alerts_line() {
  local cpu="$1" mempct="$2" swappct="$3" diskpct="$4"
  local alerts=()

  (( cpu >= 90 )) && alerts+=("CPU ${cpu}%")
  (( mempct >= 85 )) && alerts+=("RAM ${mempct}%")
  (( swappct >= 40 )) && alerts+=("Swap ${swappct}%")
  (( diskpct >= 85 )) && alerts+=("Disk ${diskpct}%")

  if (( ${#alerts[@]} == 0 )); then
    if theme_use_color; then
      printf '%sOK%s' "${THEME_SUCCESS}" "${THEME_RESET}"
    else
      printf 'OK'
    fi
  else
    local i=0
    for i in "${!alerts[@]}"; do
      if theme_use_color; then
        if [[ "${alerts[i]}" == CPU* || "${alerts[i]}" == RAM* ]]; then
          printf '%s%s%s' "${THEME_ERROR}" "${alerts[i]}" "${THEME_RESET}"
        else
          printf '%s%s%s' "${THEME_WARN}" "${alerts[i]}" "${THEME_RESET}"
        fi
      else
        printf '%s' "${alerts[i]}"
      fi
      (( i + 1 < ${#alerts[@]} )) && printf '  '
    done
  fi
}

_mon_kv() {
  local key="$1"
  local value="$2"
  if theme_use_color; then
    printf '%s%s:%s %s%s%s' \
      "${THEME_MUTED}" "${key}" "${THEME_RESET}" \
      "${THEME_ACCENT}" "${value}" "${THEME_RESET}"
  else
    printf '%s: %s' "${key}" "${value}"
  fi
}

header() {
  clear
  local now_mpls now_dubai host kern up
  now_mpls=$(TZ=America/Chicago date "+%I:%M:%S %p %a %b %d %Y [%Z]")
  now_dubai=$(TZ=Asia/Dubai date "+%I:%M:%S %p %a %b %d %Y [%Z]")
  host="$(hostname 2>/dev/null || echo "-")"
  kern="$(uname -r 2>/dev/null || echo "-")"
  up="$(uptime_pretty)"

  local cpu mem_used mem_tot mem_avail mem_pct mem_bc
  local sw_used sw_tot sw_pct
  local load1 load5 load15
  local psi_cpu psi_mem psi_io
  local iface diskdev
  local diskpct

  cpu="$(cpu_total)"
  read -r mem_used mem_tot mem_avail mem_pct mem_bc < <(mem_stats)
  read -r sw_used sw_tot sw_pct < <(swap_stats)
  read -r load1 load5 load15 < <(load_line)
  read -r psi_cpu psi_mem psi_io < <(psi_avg10)
  iface="$(primary_iface)"
  diskdev="$(pick_disk)"
  diskpct="$(root_disk_pct)"

  if theme_use_color; then
    printf '%s⚙ System monitor%s\n' "${THEME_ACCENT}" "${THEME_RESET}"
  else
    echo "System monitor"
  fi
  _mon_hr
  _mon_kv "Host" "${host}"; printf '  '
  _mon_kv "Kernel" "${kern}"; printf '  '
  _mon_kv "Uptime" "${up}"; printf '  '
  _mon_kv "Refresh" "${INTERVAL}s"
  echo
  _mon_kv "Minneapolis" "${now_mpls}"; printf '   '
  _mon_kv "Dubai" "${now_dubai}"
  _mon_hr

  if theme_use_color; then
    printf '%sCPU :%s %3s%% [%s]    %sLoad:%s %s %s %s%s\n' \
      "${THEME_MUTED}" "${THEME_RESET}" "$cpu" "$(bar "$cpu" 18)" \
      "${THEME_MUTED}" "${THEME_RESET}" \
      "${THEME_ACCENT}" "$load1" "$load5" "$load15" "${THEME_RESET}"
  else
    printf 'CPU : %3s%% [%s]    Load: %s %s %s\n' \
      "$cpu" "$(bar "$cpu" 18)" "$load1" "$load5" "$load15"
  fi

  if theme_use_color; then
    printf '%sRAM :%s %3s%% [%s]    %sUsed:%s %s/%s MiB  %sAvail:%s %s MiB\n' \
      "${THEME_MUTED}" "${THEME_RESET}" "$mem_pct" "$(bar "$mem_pct" 18)" \
      "${THEME_MUTED}" "${THEME_RESET}" \
      "${THEME_ACCENT}" "$mem_used" "$mem_tot" "${THEME_RESET}" \
      "${THEME_MUTED}" "${THEME_RESET}" \
      "${THEME_ACCENT}" "$mem_avail" "${THEME_RESET}"
  else
    printf 'RAM : %3s%% [%s]    Used: %s/%s MiB  Avail: %s MiB\n' \
      "$mem_pct" "$(bar "$mem_pct" 18)" "$mem_used" "$mem_tot" "$mem_avail"
  fi

  if theme_use_color; then
    printf '%sSwap:%s %3s%% [%s]    %sUsed:%s %s/%s MiB  %sPSI10:%s CPU:%s MEM:%s IO:%s\n' \
      "${THEME_MUTED}" "${THEME_RESET}" "$sw_pct" "$(bar "$sw_pct" 18)" \
      "${THEME_MUTED}" "${THEME_RESET}" \
      "${THEME_ACCENT}" "$sw_used" "$sw_tot" "${THEME_RESET}" \
      "${THEME_MUTED}" "${THEME_RESET}" \
      "${THEME_ACCENT}" "$psi_cpu" "$psi_mem" "$psi_io" "${THEME_RESET}"
  else
    printf 'Swap: %3s%% [%s]    Used: %s/%s MiB  PSI10: CPU:%s MEM:%s IO:%s\n' \
      "$sw_pct" "$(bar "$sw_pct" 18)" "$sw_used" "$sw_tot" "$psi_cpu" "$psi_mem" "$psi_io"
  fi

  if theme_use_color; then
    printf '%sDisk:%s %3s%% [%s]    %sNet:%s %s  %sConn:%s %s  %sIO:%s %s\n' \
      "${THEME_MUTED}" "${THEME_RESET}" "$diskpct" "$(bar "$diskpct" 18)" \
      "${THEME_MUTED}" "${THEME_RESET}" \
      "${THEME_ACCENT}" "$(net_rate_line "$iface")" "${THEME_RESET}" \
      "${THEME_MUTED}" "${THEME_RESET}" \
      "${THEME_ACCENT}" "$(conn_counts)" "${THEME_RESET}" \
      "${THEME_MUTED}" "${THEME_RESET}" \
      "${THEME_ACCENT}" "$(disk_io_rate "$diskdev")" "${THEME_RESET}"
  else
    printf 'Disk: %3s%% [%s]    Net: %s  Conn: %s  IO: %s\n' \
      "$diskpct" "$(bar "$diskpct" 18)" "$(net_rate_line "$iface")" "$(conn_counts)" "$(disk_io_rate "$diskdev")"
  fi

  if theme_use_color; then
    printf '%sTemp:%s %s%s%s\n' \
      "${THEME_MUTED}" "${THEME_RESET}" \
      "${THEME_ACCENT}" "$(temps_line)" "${THEME_RESET}"
    printf '%sBuff/Cache:%s %s%s MiB%s\n' \
      "${THEME_MUTED}" "${THEME_RESET}" \
      "${THEME_ACCENT}" "$mem_bc" "${THEME_RESET}"
  else
    printf 'Temp: %s\n' "$(temps_line)"
    printf 'Buff/Cache: %s MiB\n' "$mem_bc"
  fi

  _mon_hr
  if theme_use_color; then
    printf '%sAlerts:%s ' "${THEME_MUTED}" "${THEME_RESET}"
  else
    printf 'Alerts: '
  fi
  alerts_line "$cpu" "$mem_pct" "$sw_pct" "$diskpct"
  echo
  _mon_hr
}

while true; do
  header || true
  spotlight || true
  disk_table || true
  sleep "$INTERVAL"
done

