#!/usr/bin/env bash
# lib/health_snapshot.sh — lightweight runtime health snapshot + dashboard
# Version: 0.1.1
#
# Quiet startup snapshot for run.sh and explicit System menu actions.
# Writes:
#   runtime/health/latest.json
#   runtime/health/latest.txt
#   runtime/health/history/<stamp>.json
#   runtime/health/history/<stamp>.txt
#
# Do not execute directly.

if [[ -n "${FEDORA_HEALTH_SNAPSHOT_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_HEALTH_SNAPSHOT_SH_LOADED=1

_HEALTH_SNAPSHOT_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_HEALTH_SNAPSHOT_LIB_DIR}/common.sh"
# shellcheck source=theme.sh
source "${_HEALTH_SNAPSHOT_LIB_DIR}/theme.sh"
# shellcheck source=health.sh
source "${_HEALTH_SNAPSHOT_LIB_DIR}/health.sh"

HEALTH_SNAPSHOT_ROOT="${HEALTH_SNAPSHOT_ROOT:-$(fedora_toolkit_root)/runtime/health}"

health_snapshot_dir() { printf '%s\n' "${HEALTH_SNAPSHOT_ROOT}"; }
health_snapshot_history_dir() { printf '%s/history\n' "$(health_snapshot_dir)"; }
health_snapshot_latest_json() { printf '%s/latest.json\n' "$(health_snapshot_dir)"; }
health_snapshot_latest_txt() { printf '%s/latest.txt\n' "$(health_snapshot_dir)"; }

health_snapshot_ensure_dirs() {
  mkdir -p "$(health_snapshot_dir)" "$(health_snapshot_history_dir)"
}

health_snapshot_json_escape() {
  local s="${1-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "${s}"
}

health_snapshot_severity_rank() {
  case "$1" in
    BAD) printf '3\n' ;;
    WARN) printf '2\n' ;;
    NOTE) printf '1\n' ;;
    *) printf '0\n' ;;
  esac
}

health_snapshot_worst_status() {
  local worst="OK" cand
  for cand in "$@"; do
    if (( $(health_snapshot_severity_rank "${cand}") > $(health_snapshot_severity_rank "${worst}") )); then
      worst="${cand}"
    fi
  done
  printf '%s\n' "${worst}"
}

health_snapshot_fs_status() {
  local mount="$1" pct="$2"
  local warn=75 bad=90
  case "${mount}" in
    /boot|/boot/efi) warn=70; bad=85 ;;
  esac
  if (( pct >= bad )); then
    printf 'BAD\n'
  elif (( pct >= warn )); then
    printf 'WARN\n'
  else
    printf 'OK\n'
  fi
}

health_snapshot_ram_status() {
  local avail_bytes="$1"
  local warn=$((8 * 1024 * 1024 * 1024))
  local bad=$((4 * 1024 * 1024 * 1024))
  if (( avail_bytes < bad )); then
    printf 'BAD\n'
  elif (( avail_bytes < warn )); then
    printf 'WARN\n'
  else
    printf 'OK\n'
  fi
}

health_snapshot_swap_status() {
  local used_bytes="$1" total_bytes="$2"
  local pct=0
  (( total_bytes > 0 )) && pct=$(( used_bytes * 100 / total_bytes ))
  if (( used_bytes == 0 )); then
    printf 'OK\n'
  elif (( pct >= 25 )); then
    printf 'WARN\n'
  else
    printf 'NOTE\n'
  fi
}

health_snapshot_mount_source() {
  local src
  src="$(findmnt -no SOURCE "$1" 2>/dev/null | head -n 1 || true)"
  src="${src%%\[*}"
  printf '%s\n' "${src}"
}

health_snapshot_base_disk_from_source() {
  local src="$1" resolved parent chain_disk
  [[ -n "${src}" ]] || return 0
  resolved="$(readlink -f "${src}" 2>/dev/null || printf '%s' "${src}")"
  chain_disk="$(lsblk -s -nrdo NAME,TYPE "${resolved}" 2>/dev/null | awk '$2=="disk"{print $1}' | tail -n 1 || true)"
  if [[ -n "${chain_disk}" ]]; then
    printf '%s\n' "${chain_disk}"
    return 0
  fi
  while true; do
    parent="$(lsblk -no PKNAME "${resolved}" 2>/dev/null | head -n 1 || true)"
    [[ -n "${parent}" ]] || break
    resolved="/dev/${parent}"
  done
  basename "${resolved}"
}

health_snapshot_disk_kind() {
  local disk="$1" rota
  rota="$(lsblk -dn -o ROTA "/dev/${disk}" 2>/dev/null | awk 'NR==1{print $1}' || true)"
  case "${rota}" in
    0) printf 'SSD\n' ;;
    1) printf 'HDD\n' ;;
    *) printf 'Drive\n' ;;
  esac
}

health_snapshot_disk_size() {
  local disk="$1"
  lsblk -dn -o SIZE "/dev/${disk}" 2>/dev/null | awk 'NR==1{print $1}' || printf 'unknown\n'
}

health_snapshot_compact_dir_lines() {
  local base="$1" limit="$2"
  local timeout_sec="${3:-${FEDORA_HEALTH_DU_TIMEOUT:-12}}"
  if have timeout; then
    timeout "${timeout_sec}" du -xhd1 "${base}" 2>/dev/null \
      | sort -h \
      | awk -v base="${base}" '$1 != "0" && $2 != base {print $1 "\t" $2}' \
      | tail -n "${limit}" || true
  else
    du -xhd1 "${base}" 2>/dev/null \
      | sort -h \
      | awk -v base="${base}" '$1 != "0" && $2 != base {print $1 "\t" $2}' \
      | tail -n "${limit}" || true
  fi
}

health_snapshot_top_memory_lines() {
  ps -eo comm=,rss= \
    | awk '{rss[$1]+=$2} END {for (cmd in rss) printf "%s\t%.1fM RSS\n", cmd, rss[cmd]/1024}' \
    | sort -t$'\t' -k2,2nr \
    | head -8
}

health_snapshot_dnf_cache_size() {
  local size=""
  size="$(du -sh /var/cache/dnf 2>/dev/null | awk 'NR==1{print $1}' || true)"
  [[ -n "${size}" ]] || size="unknown"
  printf '%s\n' "${size}"
}

health_snapshot_journal_size() {
  local size=""
  size="$(journalctl --disk-usage 2>/dev/null | sed 's/Archived and active journals take up //; s/ in the file system.//' || true)"
  [[ -n "${size}" ]] || size="unknown"
  printf '%s\n' "${size}"
}

health_snapshot_mysql_note() {
  local data_src mysql_src data_disk mysql_disk
  data_src="$(health_snapshot_mount_source /data)"
  mysql_src="$(health_snapshot_mount_source /var/lib/mysql)"
  if [[ -n "${mysql_src}" ]]; then
    if [[ "${mysql_src}" == "${data_src}" && -n "${data_src}" ]]; then
      printf 'NOTE /var/lib/mysql is mounted from the same source as /data.\n'
      return 0
    fi
    data_disk="$(health_snapshot_base_disk_from_source "${data_src}")"
    mysql_disk="$(health_snapshot_base_disk_from_source "${mysql_src}")"
    if [[ -n "${data_disk}" && "${data_disk}" == "${mysql_disk}" ]]; then
      printf 'NOTE /var/lib/mysql is mounted from the same backing drive as /data.\n'
      return 0
    fi
    printf 'NOTE /var/lib/mysql is mounted separately from /data.\n'
    return 0
  fi
  if findmnt -n /data >/dev/null 2>&1; then
    printf 'NOTE /var/lib/mysql is not a separate mount; /data is mounted.\n'
  fi
}

health_snapshot_status_line_from_file() {
  local path line
  path="$(health_snapshot_latest_json)"
  [[ -f "${path}" ]] || return 1
  line="$(sed -n 's/.*"compact_status":"\([^"]*\)".*/\1/p' "${path}" | head -n 1)"
  [[ -n "${line}" ]] || return 1
  printf '%s\n' "${line}"
}

health_snapshot_write_files() {
  local root="$1" stamp="$2" write_history="$3" txt="$4" json="$5"
  local latest_txt latest_json hist_txt hist_json
  latest_txt="$(health_snapshot_latest_txt)"
  latest_json="$(health_snapshot_latest_json)"
  printf '%s\n' "${txt}" > "${latest_txt}"
  printf '%s\n' "${json}" > "${latest_json}"
  if (( write_history )); then
    hist_txt="$(health_snapshot_history_dir)/${stamp}.txt"
    hist_json="$(health_snapshot_history_dir)/${stamp}.json"
    printf '%s\n' "${txt}" > "${hist_txt}"
    printf '%s\n' "${json}" > "${hist_json}"
  fi
}

health_snapshot_generate() {
  local stamp="$1"
  local mode="${2:-quick}"
  local write_history="${3:-0}"
  local verbose="${4:-0}"

  local host os kernel uptime
  local mem_total_h mem_used_h mem_avail_h mem_total_b mem_used_b mem_avail_b
  local swap_total_h swap_used_h swap_free_h swap_total_b swap_used_b swap_free_b
  local mem_status swap_status overall_status compact_status data_state
  local dnf_cache journal_size mysql_note
  local root_pct root_avail_h
  local line

  local -a fs_mounts=() fs_status=() fs_size=() fs_used=() fs_free=() fs_pct=() fs_fstype=()
  local -a drive_lines=() system_areas=() home_areas=() top_mem=() summary_lines=()
  local mount fstype size used avail pct status

  health_snapshot_ensure_dirs

  host="$(health_hostname)"
  os="$(health_os_pretty)"
  kernel="$(health_kernel)"
  uptime="$(health_uptime | sed 's/^up //')"

  read -r mem_total_b mem_used_b _ _ _ mem_avail_b < <(free -b | awk 'NR==2 {print $2,$3,$4,$5,$6,$7}')
  mem_total_h="$(free -h | awk 'NR==2{print $2}')"
  mem_used_h="$(free -h | awk 'NR==2{print $3}')"
  mem_avail_h="$(free -h | awk 'NR==2{print $7}')"
  mem_status="$(health_snapshot_ram_status "${mem_avail_b}")"

  read -r swap_total_b swap_used_b swap_free_b < <(free -b | awk 'NR==3 {print $2,$3,$4}')
  swap_total_h="$(free -h | awk 'NR==3{print $2}')"
  swap_used_h="$(free -h | awk 'NR==3{print $3}')"
  swap_free_h="$(free -h | awk 'NR==3{print $4}')"
  swap_status="$(health_snapshot_swap_status "${swap_used_b:-0}" "${swap_total_b:-0}")"

  while IFS= read -r line; do
    mount="$(awk '{print $7}' <<< "${line}")"
    fstype="$(awk '{print $2}' <<< "${line}")"
    size="$(awk '{print $3}' <<< "${line}")"
    used="$(awk '{print $4}' <<< "${line}")"
    avail="$(awk '{print $5}' <<< "${line}")"
    pct="$(awk '{gsub(/%/,"",$6); print $6}' <<< "${line}")"
    status="$(health_snapshot_fs_status "${mount}" "${pct}")"
    fs_mounts+=("${mount}")
    fs_status+=("${status}")
    fs_size+=("${size}")
    fs_used+=("${used}")
    fs_free+=("${avail}")
    fs_pct+=("${pct}")
    fs_fstype+=("${fstype}")
  done < <(
    df -hT -x tmpfs -x devtmpfs -x efivarfs 2>/dev/null | awk '
      NR > 1 && ($7=="/" || $7=="/home" || $7=="/boot" || $7=="/boot/efi" || $7=="/data" || $7=="/var/lib/mysql") {print}
    '
  )

  if [[ "${mode}" == full || "${mode}" == export ]]; then
    while IFS= read -r line; do
      [[ -n "${line}" ]] || continue
      system_areas+=("${line}")
    done < <(health_snapshot_compact_dir_lines / 6)

    while IFS= read -r line; do
      [[ -n "${line}" ]] || continue
      home_areas+=("${line}")
    done < <(health_snapshot_compact_dir_lines "${HOME}" 8)
  fi

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    top_mem+=("${line}")
  done < <(health_snapshot_top_memory_lines)

  dnf_cache="$(health_snapshot_dnf_cache_size)"
  journal_size="$(health_snapshot_journal_size)"
  mysql_note="$(health_snapshot_mysql_note || true)"

  local root_src home_src data_src mysql_src root_disk data_disk root_kind data_kind root_size data_size
  root_src="$(health_snapshot_mount_source /)"
  home_src="$(health_snapshot_mount_source /home)"
  data_src="$(health_snapshot_mount_source /data)"
  mysql_src="$(health_snapshot_mount_source /var/lib/mysql)"
  root_disk="$(health_snapshot_base_disk_from_source "${root_src}")"
  data_disk="$(health_snapshot_base_disk_from_source "${data_src}")"

  if [[ -n "${root_disk}" ]]; then
    root_kind="$(health_snapshot_disk_kind "${root_disk}")"
    root_size="$(health_snapshot_disk_size "${root_disk}")"
    drive_lines+=("${root_kind}  ${root_disk}   ${root_size}  Fedora system drive")
    if [[ -n "${home_src}" && "$(health_snapshot_base_disk_from_source "${home_src}")" == "${root_disk}" ]]; then
      drive_lines+=("     └─ backs / and /home")
    else
      drive_lines+=("     └─ backs /")
    fi
  fi

  if [[ -n "${data_disk}" && "${data_disk}" != "${root_disk}" ]]; then
    data_kind="$(health_snapshot_disk_kind "${data_disk}")"
    data_size="$(health_snapshot_disk_size "${data_disk}")"
    drive_lines+=("")
    drive_lines+=("${data_kind}  ${data_disk}   ${data_size}  DATA drive")
    if [[ -n "${mysql_src}" && "$(health_snapshot_base_disk_from_source "${mysql_src}")" == "${data_disk}" ]]; then
      drive_lines+=("     └─ mounted at /data and also backs /var/lib/mysql")
    else
      drive_lines+=("     └─ mounted at /data")
    fi
  fi

  root_pct="unknown"
  data_state="/data not mounted"
  root_avail_h="${mem_avail_h}"
  for mount in "${!fs_mounts[@]}"; do
    if [[ "${fs_mounts[$mount]}" == "/" ]]; then
      root_pct="${fs_pct[$mount]}"
    fi
    if [[ "${fs_mounts[$mount]}" == "/data" ]]; then
      data_state="/data mounted"
    fi
  done

  overall_status="$(health_snapshot_worst_status "${mem_status}" "${swap_status}" "${fs_status[@]}")"
  compact_status="Health: ${overall_status} · root ${root_pct}% used · RAM ${root_avail_h} available · ${data_state}"

  summary_lines+=("${overall_status} Disk space summary computed from key mounts.")
  case "${mem_status}" in
    BAD) summary_lines+=("BAD RAM available is under 4G.") ;;
    WARN) summary_lines+=("WARN RAM available is under 8G.") ;;
    *) summary_lines+=("OK RAM available is healthy.") ;;
  esac
  case "${swap_status}" in
    WARN) summary_lines+=("WARN Swap usage is elevated.") ;;
    NOTE) summary_lines+=("NOTE Swap is in use.") ;;
    *) summary_lines+=("OK Swap is unused.") ;;
  esac
  if [[ -n "${mysql_note}" ]]; then
    summary_lines+=("${mysql_note%$'\n'}")
  fi

  local txt=""
  txt+="══════════════════════════════════════════════════════"$'\n'
  txt+="◉ Disk and memory summary"$'\n'
  txt+="──────────────────────────────────────────────────────"$'\n'
  txt+="Host    : ${host}"$'\n'
  txt+="OS      : ${os}"$'\n'
  txt+="Kernel  : ${kernel}"$'\n'
  txt+="Uptime  : ${uptime}"$'\n'
  txt+="Generated: $(date -Is)"$'\n'
  txt+="Compact : ${compact_status}"$'\n'
  txt+="──────────────────────────────────────────────────────"$'\n\n'
  txt+="[System]"$'\n'
  txt+="Host    : ${host}"$'\n'
  txt+="Fedora  : ${os}"$'\n'
  txt+="Kernel  : ${kernel}"$'\n'
  txt+="Uptime  : ${uptime}"$'\n\n'
  txt+="[Memory]"$'\n'
  txt+="${mem_status}   RAM   ${mem_total_h} total · ${mem_used_h} used · ${mem_avail_h} available"$'\n'
  txt+="${swap_status}   Swap  ${swap_total_h} total · ${swap_used_h} used · ${swap_free_h} free"$'\n\n'
  txt+="[Filesystems]"$'\n'
  for mount in "${!fs_mounts[@]}"; do
    txt+="${fs_status[$mount]}   ${fs_mounts[$mount]} ${fs_size[$mount]} total · ${fs_used[$mount]} used · ${fs_free[$mount]} free · ${fs_pct[$mount]}%"$'\n'
  done
  [[ -n "${mysql_note}" ]] && txt+="${mysql_note}"
  txt+=$'\n'
  txt+="[Drives]"$'\n'
  for line in "${drive_lines[@]}"; do
    txt+="${line}"$'\n'
  done
  txt+=$'\n'
  if [[ "${mode}" == full || "${mode}" == export ]]; then
    txt+="[Large system areas]"$'\n'
    if ((${#system_areas[@]} == 0)); then
      txt+="(no large directories detected)"$'\n'
    else
      for line in "${system_areas[@]}"; do txt+="${line}"$'\n'; done
    fi
    txt+=$'\n'
    txt+="[Large home areas]"$'\n'
    if ((${#home_areas[@]} == 0)); then
      txt+="(no large directories detected)"$'\n'
    else
      for line in "${home_areas[@]}"; do txt+="${line}"$'\n'; done
    fi
  else
    txt+="[Large areas]"$'\n'
    txt+="(skipped in quick mode — use --export or refresh with mode=full)"$'\n'
  fi
  txt+=$'\n'
  txt+="[Cleanup targets]"$'\n'
  txt+="OK   DNF cache    ${dnf_cache}"$'\n'
  txt+="OK   Journal      ${journal_size}"$'\n\n'
  txt+="[Top memory groups]"$'\n'
  for line in "${top_mem[@]}"; do
    txt+="$(cut -f1 <<< "${line}") $(cut -f2 <<< "${line}")"$'\n'
  done
  txt+=$'\n'
  txt+="[Summary]"$'\n'
  for line in "${summary_lines[@]}"; do txt+="${line}"$'\n'; done

  local json fs_json="" summary_json="" system_json="" home_json="" top_json="" drives_json=""
  for mount in "${!fs_mounts[@]}"; do
    [[ -n "${fs_json}" ]] && fs_json+=","
    fs_json+="{\"mount\":\"$(health_snapshot_json_escape "${fs_mounts[$mount]}")\",\"status\":\"${fs_status[$mount]}\",\"size\":\"$(health_snapshot_json_escape "${fs_size[$mount]}")\",\"used\":\"$(health_snapshot_json_escape "${fs_used[$mount]}")\",\"free\":\"$(health_snapshot_json_escape "${fs_free[$mount]}")\",\"pct\":${fs_pct[$mount]},\"fstype\":\"$(health_snapshot_json_escape "${fs_fstype[$mount]}")\"}"
  done
  for line in "${summary_lines[@]}"; do
    [[ -n "${summary_json}" ]] && summary_json+=","
    summary_json+="\"$(health_snapshot_json_escape "${line}")\""
  done
  for line in "${system_areas[@]}"; do
    [[ -n "${system_json}" ]] && system_json+=","
    system_json+="\"$(health_snapshot_json_escape "${line}")\""
  done
  for line in "${home_areas[@]}"; do
    [[ -n "${home_json}" ]] && home_json+=","
    home_json+="\"$(health_snapshot_json_escape "${line}")\""
  done
  for line in "${top_mem[@]}"; do
    [[ -n "${top_json}" ]] && top_json+=","
    top_json+="\"$(health_snapshot_json_escape "$(cut -f1 <<< "${line}") $(cut -f2 <<< "${line}")")\""
  done
  for line in "${drive_lines[@]}"; do
    [[ -n "${drives_json}" ]] && drives_json+=","
    drives_json+="\"$(health_snapshot_json_escape "${line}")\""
  done

  json="{"
  json+="\"generated_at\":\"$(date -Is)\","
  json+="\"stamp\":\"${stamp}\","
  json+="\"mode\":\"${mode}\","
  json+="\"host\":\"$(health_snapshot_json_escape "${host}")\","
  json+="\"os\":\"$(health_snapshot_json_escape "${os}")\","
  json+="\"kernel\":\"$(health_snapshot_json_escape "${kernel}")\","
  json+="\"uptime\":\"$(health_snapshot_json_escape "${uptime}")\","
  json+="\"overall_status\":\"${overall_status}\","
  json+="\"compact_status\":\"$(health_snapshot_json_escape "${compact_status}")\","
  json+="\"memory\":{\"status\":\"${mem_status}\",\"total\":\"$(health_snapshot_json_escape "${mem_total_h}")\",\"used\":\"$(health_snapshot_json_escape "${mem_used_h}")\",\"available\":\"$(health_snapshot_json_escape "${mem_avail_h}")\"},"
  json+="\"swap\":{\"status\":\"${swap_status}\",\"total\":\"$(health_snapshot_json_escape "${swap_total_h}")\",\"used\":\"$(health_snapshot_json_escape "${swap_used_h}")\",\"free\":\"$(health_snapshot_json_escape "${swap_free_h}")\"},"
  json+="\"filesystems\":[${fs_json}],"
  json+="\"data_mysql_note\":\"$(health_snapshot_json_escape "${mysql_note}")\","
  json+="\"drives\":[${drives_json}],"
  json+="\"large_system_areas\":[${system_json}],"
  json+="\"large_home_areas\":[${home_json}],"
  json+="\"cleanup\":{\"dnf_cache\":\"$(health_snapshot_json_escape "${dnf_cache}")\",\"journal\":\"$(health_snapshot_json_escape "${journal_size}")\"},"
  json+="\"top_memory_groups\":[${top_json}],"
  json+="\"summary\":[${summary_json}]"
  json+="}"

  health_snapshot_write_files "$(fedora_toolkit_root)" "${stamp}" "${write_history}" "${txt}" "${json}"
  if (( verbose )); then
    info "Health snapshot updated: $(health_snapshot_latest_txt)"
  fi
}

health_snapshot_refresh() {
  local mode="${1:-quick}"
  local write_history="${2:-1}"
  local verbose="${3:-0}"
  health_snapshot_generate "$(date +%Y%m%d_%H%M%S)" "${mode}" "${write_history}" "${verbose}"
}

health_snapshot_startup_refresh() {
  [[ "${FEDORA_HEALTH_STARTUP:-1}" == 0 ]] && return 0
  health_snapshot_refresh quick 0 "${FEDORA_VERBOSE:-0}" >/dev/null 2>&1 || true
}

health_snapshot_export_full_report() {
  local stamp="${1:-$(date +%Y%m%d_%H%M%S)}"
  local out_dir out_txt
  out_dir="$(health_snapshot_history_dir)"
  out_txt="${out_dir}/${stamp}_full.txt"
  health_snapshot_refresh export 1 0 >/dev/null 2>&1 || true
  {
    echo "══════════════════════════════════════════════════════"
    echo "◉ Full health diagnostic report"
    echo "──────────────────────────────────────────────────────"
    echo "Generated: $(date -Is)"
    echo "Root: $(fedora_toolkit_root)"
    echo
    cat "$(health_snapshot_latest_txt)" 2>/dev/null || true
    echo
    echo "[findmnt]"
    findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null || true
    echo
    echo "[lsblk]"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS 2>/dev/null || true
    echo
    echo "[df full]"
    df -hT -x tmpfs -x devtmpfs -x efivarfs 2>/dev/null || true
    echo
    echo "[Top processes]"
    ps -eo pid,comm,%cpu,%mem --sort=-%mem --no-headers 2>/dev/null | head -20 || true
    echo
    echo "[Large system areas privileged]"
    if sudo -n true 2>/dev/null; then
      sudo -n du -xhd1 / 2>/dev/null | sort -h | awk '$1 != "0" && $2 != "/" {print}' | tail -10
    elif [[ -t 0 ]]; then
      if sudo du -xhd1 / 2>/dev/null | sort -h | awk '$1 != "0" && $2 != "/" {print}' | tail -10; then
        true
      else
        echo "sudo scan unavailable"
      fi
    else
      echo "sudo scan unavailable (non-interactive)"
    fi
  } > "${out_txt}"
  printf '%s\n' "${out_txt}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
