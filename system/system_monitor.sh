#!/usr/bin/env bash
# system_monitor.sh — Live system dashboard (CPU, RAM, disk, network, PSI)
# Version: 0.1.1
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

# ---- color system ----
BOLD=$(tput bold 2>/dev/null || true)
DIM=$(tput dim 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)

FG_RED=$(tput setaf 1 2>/dev/null || true)
FG_GRN=$(tput setaf 2 2>/dev/null || true)
FG_YLW=$(tput setaf 3 2>/dev/null || true)
FG_BLU=$(tput setaf 4 2>/dev/null || true)
FG_CYN=$(tput setaf 6 2>/dev/null || true)
FG_WHT=$(tput setaf 7 2>/dev/null || true)

TITLE="${FG_BLU}${BOLD}"
ACCENT="${FG_CYN}${BOLD}"
OK="${FG_GRN}${BOLD}"
WARN="${FG_YLW}${BOLD}"
BAD="${FG_RED}${BOLD}"
MUTED="${DIM}${FG_WHT}"

cols() { tput cols 2>/dev/null || echo 100; }
hr()   { printf "%s\n" "────────────────────────────────────────────────────────────────────────────────────────────────────────" | cut -c1-"$(cols)"; }
safe() { "$@" 2>/dev/null || true; }

# ---- bars ----
bar() {
  local pct="${1:-0}" width="${2:-18}"
  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100
  local filled=$(( (pct*width)/100 ))
  local empty=$(( width-filled ))

  local color="${OK}"
  if (( pct >= 85 )); then color="${BAD}"
  elif (( pct >= 70 )); then color="${WARN}"
  fi

  printf "%s" "$color"
  local i
  for ((i = 0; i < filled; i++)); do printf '█'; done
  printf "%s" "$RESET"
  for ((i = 0; i < empty; i++)); do printf '░'; done
}

# ---- metrics ----
cpu_total() {
  local pct
  if pct="$(health_cpu_usage_pct 2>/dev/null)"; then
    awk -v p="${pct}" 'BEGIN{printf "%.0f", p+0}'
    return 0
  fi
  if command -v mpstat >/dev/null 2>&1; then
    safe mpstat 1 1 | awk '/Average:/ && $3=="all"{printf "%.0f", 100-$12}' || echo 0
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
  safe awk '{
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
  echo "${TITLE}Disk${RESET}"
  if command -v df >/dev/null 2>&1; then
    printf "  %-14s %-6s %-6s %-6s %-5s %s\n" "MOUNT" "TYPE" "SIZE" "USED" "USE%" "DEVICE"
    safe df -hT -x tmpfs -x devtmpfs | awk '
      NR==1{next}
      $7=="/" || $7=="/home" || $7=="/boot" || $7=="/boot/efi" {
        gsub("%","",$6);
        printf "  %-14.14s %-6s %-6s %-6s %-5s %s\n",$7,$2,$3,$4,$6"%",$1
      }'
  else
    echo "  ${MUTED}df not found${RESET}"
  fi
  hr
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
  tcp="$(safe ss -tan | awk 'NR>1{c++} END{print c+0}')"
  udp="$(safe ss -uan | awk 'NR>1{c++} END{print c+0}')"
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
  echo "${TITLE}Spotlight${RESET}  ${MUTED}(${TOP_KW_REGEX})${RESET}"
  printf "  %-7s %-24s %7s %7s\n" "PID" "COMMAND" "%CPU" "%MEM"

  safe ps -eo pid,comm,%cpu,%mem --sort=-%cpu --no-headers | \
    awk -v r="$TOP_KW_REGEX" '$2 ~ r {printf "  %-7s %-24.24s %7.1f %7.1f\n",$1,$2,$3,$4}' | \
    head -n 8

  hr
}

alerts_line() {
  local cpu="$1" mempct="$2" swappct="$3" diskpct="$4"
  local alerts=()

  (( cpu >= 90 )) && alerts+=("${BAD}CPU ${cpu}%${RESET}")
  (( mempct >= 85 )) && alerts+=("${BAD}RAM ${mempct}%${RESET}")
  (( swappct >= 40 )) && alerts+=("${WARN}Swap ${swappct}%${RESET}")
  (( diskpct >= 85 )) && alerts+=("${WARN}Disk ${diskpct}%${RESET}")

  if (( ${#alerts[@]} == 0 )); then
    printf "${OK}OK${RESET}"
  else
    printf "%s" "${alerts[*]}"
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

  echo "${TITLE}Fedora Linux · System Operation Monitor${RESET}"
  hr
  echo "${MUTED}Host:${RESET} ${ACCENT}${host}${RESET}  ${MUTED}Kernel:${RESET} ${ACCENT}${kern}${RESET}  ${MUTED}Uptime:${RESET} ${ACCENT}${up}${RESET}  ${MUTED}Refresh:${RESET} ${ACCENT}${INTERVAL}s${RESET}"
  echo "${MUTED}Minneapolis:${RESET} ${ACCENT}${now_mpls}${RESET}   ${MUTED}Dubai:${RESET} ${ACCENT}${now_dubai}${RESET}"
  hr

  # KPI rows (aligned)
  printf "${MUTED}CPU :${RESET} %3s%% [%s]    ${MUTED}Load:${RESET} ${ACCENT}%s %s %s${RESET}\n" \
    "$cpu" "$(bar "$cpu" 18)" "$load1" "$load5" "$load15"

  printf "${MUTED}RAM :${RESET} %3s%% [%s]    ${MUTED}Used:${RESET} ${ACCENT}%s/%s MiB${RESET}  ${MUTED}Avail:${RESET} ${ACCENT}%s MiB${RESET}\n" \
    "$mem_pct" "$(bar "$mem_pct" 18)" "$mem_used" "$mem_tot" "$mem_avail"

  printf "${MUTED}Swap:${RESET} %3s%% [%s]    ${MUTED}Used:${RESET} ${ACCENT}%s/%s MiB${RESET}  ${MUTED}PSI10:${RESET} ${ACCENT}CPU:%s MEM:%s IO:%s${RESET}\n" \
    "$sw_pct" "$(bar "$sw_pct" 18)" "$sw_used" "$sw_tot" "$psi_cpu" "$psi_mem" "$psi_io"

  printf "${MUTED}Disk:${RESET} %3s%% [%s]    ${MUTED}Net:${RESET} ${ACCENT}%s${RESET}  ${MUTED}Conn:${RESET} ${ACCENT}%s${RESET}  ${MUTED}IO:${RESET} ${ACCENT}%s${RESET}\n" \
    "$diskpct" "$(bar "$diskpct" 18)" "$(net_rate_line "$iface")" "$(conn_counts)" "$(disk_io_rate "$diskdev")"

  printf "${MUTED}Temp:${RESET} ${ACCENT}%s${RESET}\n" "$(temps_line)"
  printf "${MUTED}Buff/Cache:${RESET} ${ACCENT}%s MiB${RESET}\n" "$mem_bc"

  hr
  echo -n "${MUTED}Alerts:${RESET} "
  alerts_line "$cpu" "$mem_pct" "$sw_pct" "$diskpct"
  echo
  hr
}

while true; do
  header || true
  spotlight || true
  disk_table || true
  sleep "$INTERVAL"
done

