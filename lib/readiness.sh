#!/usr/bin/env bash
# lib/readiness.sh — workstation readiness probes (read-only by default)
# Version: 0.2.4
#
# Fedora workstation control plane: daily driver, btrfs, LUKS, VirtualBox,
# package noise, post-update validation. Not Mercury (no backup/DR manifests).
#
# Source after lib/common.sh and lib/health.sh:
#   source "${FEDORA_ROOT}/lib/readiness.sh"
#
# Do not execute directly.

if [[ -n "${FEDORA_READINESS_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_READINESS_SH_LOADED=1

_READINESS_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_READINESS_LIB_DIR}/common.sh"
# shellcheck source=health.sh
source "${_READINESS_LIB_DIR}/health.sh"
# shellcheck source=theme.sh
source "${_READINESS_LIB_DIR}/theme.sh"
# shellcheck source=services.sh
source "${_READINESS_LIB_DIR}/services.sh"

# ---------- host identity ----------
readiness_dmi_value_is_placeholder() {
  local value="${1:-}"
  case "${value}" in
    ""|unknown|"Not Specified"|"System Product Name"|"To be filled by O.E.M."|"Default string") return 0 ;;
  esac
  return 1
}

readiness_host_model() {
  local model="" path
  if have hostnamectl; then
    model="$(hostnamectl status 2>/dev/null | awk -F': +' '/Hardware Model:/{print $2; exit}' || true)"
  fi
  for path in /sys/class/dmi/id/product_name /sys/devices/virtual/dmi/id/product_name; do
    if readiness_dmi_value_is_placeholder "${model}" && [[ -r "${path}" ]]; then
      model="$(tr -d '\0' < "${path}" 2>/dev/null || true)"
    fi
  done
  for path in /sys/class/dmi/id/board_name /sys/devices/virtual/dmi/id/board_name; do
    if readiness_dmi_value_is_placeholder "${model}" && [[ -r "${path}" ]]; then
      model="$(tr -d '\0' < "${path}" 2>/dev/null || true)"
    fi
  done
  if readiness_dmi_value_is_placeholder "${model}" && have dmidecode && [[ -r /sys/firmware/dmi/tables/DMI ]]; then
    model="$(dmidecode -s system-product-name 2>/dev/null | head -n 1 || true)"
  fi
  if readiness_dmi_value_is_placeholder "${model}"; then
    model="$(health_cpu_model)"
  fi
  readiness_dmi_value_is_placeholder "${model}" && model="unknown"
  printf '%s\n' "${model}"
}

# ---------- boot ----------
readiness_boot_time_summary() {
  if ! have systemd-analyze; then
    printf 'systemd-analyze not installed\n'
    return 1
  fi
  systemd-analyze 2>/dev/null | head -n 1 || true
}

readiness_boot_blame_top() {
  local n="${1:-5}"
  if ! have systemd-analyze; then
    return 1
  fi
  systemd-analyze blame 2>/dev/null | head -n "${n}" || true
}

# ---------- kernel cmdline ----------
readiness_kernel_cmdline() {
  tr '\0' ' ' < /proc/cmdline 2>/dev/null || printf 'unknown\n'
}

readiness_kernel_has_rhgb_quiet() {
  local cmd
  cmd="$(readiness_kernel_cmdline)"
  [[ "${cmd}" == *rhgb* && "${cmd}" == *quiet* ]]
}

# ---------- btrfs ----------
readiness_root_is_btrfs() {
  findmnt -n -o FSTYPE / 2>/dev/null | grep -qx btrfs
}

readiness_btrfs_device_stats() {
  local mount="${1:-/}"
  if ! have btrfs; then
    printf 'btrfs command not installed\n'
    return 1
  fi
  if ! findmnt -n "${mount}" >/dev/null 2>&1; then
    printf 'mount not found: %s\n' "${mount}"
    return 1
  fi
  if ! findmnt -n -o FSTYPE "${mount}" 2>/dev/null | grep -qx btrfs; then
    printf 'not btrfs: %s\n' "${mount}"
    return 1
  fi
  btrfs device stats "${mount}" 2>/dev/null || true
}

readiness_btrfs_scrub_status() {
  local mount="${1:-/}" out=""
  if ! have btrfs; then
    printf 'btrfs command not installed\n'
    return 1
  fi
  if ! readiness_root_is_btrfs && [[ "${mount}" == "/" ]]; then
    printf 'root is not btrfs\n'
    return 1
  fi
  out="$(btrfs scrub status "${mount}" 2>&1 || true)"
  if [[ -n "${out}" ]] && ! grep -qiE 'Permission denied|failed to open status' <<< "${out}"; then
    printf '%s\n' "${out}"
    return 0
  fi
  if [[ "${EUID}" -eq 0 ]]; then
    out="$(btrfs scrub status "${mount}" 2>&1 || true)"
  elif sudo -n true 2>/dev/null; then
    out="$(sudo -n btrfs scrub status "${mount}" 2>&1 || true)"
  else
    printf 'scrub status requires sudo (btrfs status file not readable)\n'
    return 1
  fi
  if grep -qiE 'Permission denied|failed to open status' <<< "${out}"; then
    printf 'scrub status requires sudo (btrfs status file not readable)\n'
    return 1
  fi
  [[ -n "${out}" ]] && printf '%s\n' "${out}"
}

readiness_btrfs_corruption_errs() {
  local stats line val
  stats="$(readiness_btrfs_device_stats / 2>/dev/null || true)"
  [[ -n "${stats}" ]] || return 1
  val=0
  while IFS= read -r line; do
    if [[ "${line}" == *corruption_errs* ]]; then
      val="$(awk '{print $2}' <<< "${line}")"
      break
    fi
  done <<< "${stats}"
  printf '%s\n' "${val:-unknown}"
}

# ---------- LUKS ----------
readiness_luks_uuid_from_cmdline() {
  local line uuid
  line="$(readiness_kernel_cmdline)"
  if [[ "${line}" =~ rd\.luks\.uuid=luks-([0-9a-fA-F-]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# Encrypted block device for cryptsetup (prefers stable /dev/disk/by-uuid/ path).
readiness_luks_root_device() {
  local uuid mapper part path
  if uuid="$(readiness_luks_uuid_from_cmdline 2>/dev/null)" && [[ -n "${uuid}" ]]; then
    path="/dev/disk/by-uuid/${uuid}"
    if [[ -e "${path}" ]]; then
      printf '%s\n' "${path}"
      return 0
    fi
  fi
  mapper="$(findmnt -no SOURCE / 2>/dev/null | head -n 1 | sed 's/\[.*//' || true)"
  [[ -n "${mapper}" ]] || return 1
  while IFS= read -r part; do
    [[ -n "${part}" && -b "${part}" ]] || continue
    printf '%s\n' "${part}"
    return 0
  done < <(lsblk -s -nrpo PATH,TYPE "${mapper}" 2>/dev/null | awk '$2=="part"{print $1; exit}')
  return 1
}

# Mapper path for display (e.g. /dev/mapper/luks-UUID).
readiness_luks_mapper_device() {
  local root_src
  root_src="$(findmnt -no SOURCE / 2>/dev/null | head -n 1 || true)"
  [[ -n "${root_src}" ]] || return 1
  root_src="${root_src%%\[*}"
  [[ "${root_src}" == /dev/mapper/* ]] && printf '%s\n' "${root_src}"
}

readiness_luks_keyslot_count_from_dump() {
  local dump="$1" count=""
  [[ -n "${dump}" ]] || return 1
  if ! grep -qE '^(Version:|LUKS header|Keyslots:)' <<< "${dump}"; then
    return 1
  fi
  count="$(awk -F: '/^Keyslots:/ {gsub(/^[ \t]+/,"",$2); print $2; exit}' <<< "${dump}" 2>/dev/null || true)"
  if [[ -n "${count}" ]]; then
    printf '%s\n' "${count}"
    return 0
  fi
  count="$(awk '/^[[:space:]]*[0-9]+: luks/{n++} END{if (n>0) print n}' <<< "${dump}" 2>/dev/null || true)"
  [[ -n "${count}" ]] && printf '%s\n' "${count}"
}

readiness_luks_keyslot_count() {
  local dev count dump mapper
  dev="$(readiness_luks_root_device 2>/dev/null || true)"
  [[ -n "${dev}" ]] || { printf 'unknown\n'; return 1; }
  if ! have cryptsetup; then
    printf 'unknown (cryptsetup missing)\n'
    return 1
  fi
  if [[ "${EUID}" -eq 0 ]]; then
    dump="$(cryptsetup luksDump "${dev}" 2>/dev/null || true)"
  elif sudo -n true 2>/dev/null; then
    dump="$(sudo -n cryptsetup luksDump "${dev}" 2>/dev/null || true)"
  else
    printf 'unknown\n'
    return 0
  fi
  count="$(readiness_luks_keyslot_count_from_dump "${dump}" 2>/dev/null || true)"
  if [[ -z "${count}" ]] && mapper="$(readiness_luks_mapper_device 2>/dev/null || true)" && [[ -n "${mapper}" ]]; then
    if [[ "${EUID}" -eq 0 ]]; then
      dump="$(cryptsetup luksDump "${mapper}" 2>/dev/null || true)"
    else
      dump="$(sudo -n cryptsetup luksDump "${mapper}" 2>/dev/null || true)"
    fi
    count="$(readiness_luks_keyslot_count_from_dump "${dump}" 2>/dev/null || true)"
  fi
  [[ -n "${count}" ]] || count="unknown"
  printf '%s\n' "${count}"
}

readiness_luks_keyslot_hint() {
  local count="${1:-}"
  if [[ "${count}" == "unknown" && "${EUID}" -ne 0 ]] && ! sudo -n true 2>/dev/null; then
    theme_note "Run sudo ./system/system.sh luks-readiness to show keyslot count."
  elif [[ "${count}" == "unknown" ]]; then
    theme_note "cryptsetup luksDump failed — verify LUKS device path and permissions."
  fi
}

readiness_luks_header_backup_paths() {
  local host home paths=()
  host="$(health_hostname)"
  home="$(real_home)"
  paths+=("${home}/luks_backups")
  paths+=("/data/system_backups/${host}_luks")
  printf '%s\n' "${paths[@]}"
}

readiness_luks_print_backup_instructions() {
  local dev
  dev="$(readiness_luks_root_device 2>/dev/null || true)"
  cat <<EOF
LUKS header backup (manual — read-only check does not create backups):
  1. Identify encrypted device: ${dev:-unknown}
  2. Backup header (destructive if mistyped — use a unique filename):
       sudo cryptsetup luksHeaderBackup ${dev:-/dev/sdX} \\
         --header-backup-file $(real_home)/luks_backups/$(health_hostname)_luks_header_$(date +%Y%m%d).img
  3. Copy to durable storage, e.g.:
       /data/system_backups/$(health_hostname)_luks/
  Never store passphrases in this repo or in plaintext notes on shared hosts.
EOF
}

# Returns 0 when at least one expected header backup directory contains files.
readiness_luks_header_backup_ok() {
  local path
  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    if [[ -d "${path}" ]] && find "${path}" -maxdepth 2 -type f 2>/dev/null | grep -q .; then
      return 0
    fi
  done < <(readiness_luks_header_backup_paths)
  return 1
}

# Read a passphrase from /dev/tty into a chmod 600 file (never echoed or logged).
readiness_luks_read_passphrase_to_file() {
  local dest="$1" prompt="$2"
  local pass=""
  [[ -r /dev/tty && -w /dev/tty ]] || die "Interactive terminal required (/dev/tty)"
  [[ -n "${dest}" ]] || die "readiness_luks_read_passphrase_to_file: dest required"
  printf '%s' "${prompt}" >/dev/tty
  IFS= read -rs pass </dev/tty || die "Could not read passphrase from terminal"
  printf '\n' >/dev/tty
  umask 077
  printf '%s' "${pass}" > "${dest}"
  chmod 600 "${dest}"
  pass=""
  unset pass
}

# Shred/remove LUKS key temp files and directory.
readiness_luks_cleanup_keydir() {
  local tmpdir="$1"
  local f
  [[ -n "${tmpdir}" && -d "${tmpdir}" ]] || return 0
  for f in "${tmpdir}"/*; do
    [[ -e "${f}" ]] || continue
    if have shred; then
      shred -u -f -z "${f}" 2>/dev/null || rm -f "${f}"
    else
      rm -f "${f}"
    fi
  done
  rmdir "${tmpdir}" 2>/dev/null || rm -rf "${tmpdir}"
}

# Interactive add-passphrase flow. Requires root, /dev/tty, cryptsetup.
# Never prints passphrases; does not remove keyslots.
readiness_luks_add_passphrase_interactive() {
  local dev tmpdir old_file new_file confirm_file
  local slots_before slots_after
  local ans

  [[ -t 0 && -r /dev/tty && -w /dev/tty ]] || die "--add-passphrase requires an interactive terminal (stdin and /dev/tty)"
  have cryptsetup || die "cryptsetup not installed"
  [[ "${EUID}" -eq 0 ]] || die "Run with sudo: sudo ./system/luks_readiness.sh --add-passphrase"

  dev="$(readiness_luks_root_device 2>/dev/null || true)"
  [[ -n "${dev}" ]] || die "Could not detect LUKS device for /"

  theme_report_header "LUKS add passphrase" \
    "Device: ${dev}" \
    "Adds a keyslot only · never removes existing slots"

  if readiness_luks_header_backup_ok; then
    ok "LUKS header backup found in expected location"
  else
    warn "No LUKS header backup found under expected paths"
    readiness_luks_print_backup_instructions
    printf 'Continue without a verified header backup? [y/N] ' >/dev/tty
    IFS= read -r ans </dev/tty || die "Cancelled"
    case "${ans,,}" in
      y|yes) warn "Continuing without verified header backup" ;;
      *) die "Aborted — create a header backup first" ;;
    esac
  fi

  slots_before="$(readiness_luks_keyslot_count 2>/dev/null || echo unknown)"
  theme_kv "Keyslots (before)" "${slots_before}"

  printf 'Add a new LUKS passphrase in a new keyslot? [y/N] ' >/dev/tty
  IFS= read -r ans </dev/tty || die "Cancelled"
  case "${ans,,}" in
    y|yes) ;;
    *) die "Cancelled" ;;
  esac

  tmpdir="$(mktemp -d)"
  chmod 700 "${tmpdir}"
  old_file="${tmpdir}/old.key"
  new_file="${tmpdir}/new.key"
  confirm_file="${tmpdir}/new.confirm"

  # shellcheck disable=SC2064
  trap 'readiness_luks_cleanup_keydir "${tmpdir}"' EXIT INT TERM

  readiness_luks_read_passphrase_to_file "${old_file}" "Enter current LUKS passphrase: "

  printf 'Test current passphrase before adding? [Y/n] ' >/dev/tty
  IFS= read -r ans </dev/tty || ans=""
  case "${ans,,}" in
    n|no) ;;
    *)
      if cryptsetup open --test-passphrase --key-file "${old_file}" "${dev}" 2>/dev/null; then
        ok "Current passphrase verified"
      else
        warn "Current passphrase test failed"
        printf 'Continue anyway? [y/N] ' >/dev/tty
        IFS= read -r ans </dev/tty || die "Cancelled"
        case "${ans,,}" in
          y|yes) ;;
          *) die "Cancelled" ;;
        esac
      fi
      ;;
  esac

  readiness_luks_read_passphrase_to_file "${new_file}" "Enter new LUKS passphrase: "
  readiness_luks_read_passphrase_to_file "${confirm_file}" "Confirm new LUKS passphrase: "
  if ! cmp -s "${new_file}" "${confirm_file}" 2>/dev/null; then
    die "New passphrases do not match"
  fi
  rm -f "${confirm_file}"

  printf 'Write new passphrase to a new LUKS keyslot now? [y/N] ' >/dev/tty
  IFS= read -r ans </dev/tty || die "Cancelled"
  case "${ans,,}" in
    y|yes) ;;
    *) die "Cancelled" ;;
  esac

  if cryptsetup luksAddKey "${dev}" "${new_file}" --key-file "${old_file}"; then
    ok "New keyslot added (existing slots unchanged)"
  else
    die "luksAddKey failed — no keyslot was added"
  fi

  slots_after="$(readiness_luks_keyslot_count 2>/dev/null || echo unknown)"
  theme_kv "Keyslots (after)" "${slots_after}"

  printf 'Test new passphrase now? [y/N] ' >/dev/tty
  IFS= read -r ans </dev/tty || return 0
  case "${ans,,}" in
    y|yes)
      if cryptsetup open --test-passphrase --key-file "${new_file}" "${dev}" 2>/dev/null; then
        ok "New passphrase verified"
      else
        warn "New passphrase test failed — verify at next boot if unsure"
      fi
      ;;
  esac

  trap - EXIT INT TERM
  readiness_luks_cleanup_keydir "${tmpdir}"
  echo
  theme_result_ready "LUKS add-passphrase complete"
}

# ---------- VirtualBox ----------
readiness_vbox_is_installed() {
  have rpm && rpm -q VirtualBox &>/dev/null
}

# VBoxManage --version prints multi-line WARNING text before the version line.
readiness_vbox_version() {
  local bin="${1:-}" ver=""
  [[ -n "${bin}" ]] || bin="$(cmd_binary_path VBoxManage 2>/dev/null || true)"
  [[ -n "${bin}" ]] || return 1
  ver="$("${bin}" --version 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | tail -n 1 || true)"
  [[ -n "${ver}" ]] && printf '%s\n' "${ver}"
}

readiness_vbox_char_dev_ready() {
  [[ -c /dev/vboxdrv ]]
}

# Modules loaded and VBoxManage works, but /dev/vboxdrv is missing (recoverable via vboxdrv.service).
readiness_vbox_char_dev_recoverable() {
  readiness_vbox_is_installed || return 1
  [[ -n "$(readiness_vbox_modules_loaded)" ]] || return 1
  readiness_vbox_char_dev_ready && return 1
  readiness_vbox_version >/dev/null 2>&1
}

readiness_vbox_modules_loaded() {
  lsmod 2>/dev/null | awk '/^vbox/{print}' || true
}

readiness_vbox_kernel_matches_running() {
  local running latest
  running="$(uname -r)"
  latest="$(rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V | tail -n 1 || true)"
  [[ -n "${latest}" && "${running}" == "${latest}" ]]
}

readiness_latest_installed_kernel() {
  rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V | tail -n 1 || true
}

readiness_vbox_packages_status() {
  local kver
  kver="$(uname -r)"
  rpm -q VirtualBox akmod-VirtualBox "kernel-devel-${kver}" 2>/dev/null || true
}

# ---------- package noise ----------
readonly _READINESS_PKG_PROCS=(dnf dnf5 PackageKit packagekitd dnfdragora dnf5daemon rpm)

readiness_package_noise_list() {
  local proc out found=0 line pid cmd
  for proc in "${_READINESS_PKG_PROCS[@]}"; do
    while IFS= read -r line; do
      [[ -n "${line}" ]] || continue
      pid="${line%% *}"
      cmd="${line#${pid} }"
      cmd="${cmd# }"
      [[ "${cmd}" == "${proc}"* ]] || continue
      found=1
      printf '%s\n' "${line}"
    done < <(pgrep -a -x "${proc}" 2>/dev/null || true)
  done
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    [[ "${line}" == *"pgrep"* ]] && continue
    found=1
    printf '%s\n' "${line}"
  done < <(pgrep -af '[f]latpak.*helper' 2>/dev/null || true)
  (( found )) && return 0
  return 1
}

readiness_package_noise_stop_session() {
  info "Stopping background package/update helpers for this session (packages are not removed)"
  if have systemctl; then
    if systemctl is-active --quiet packagekit.service 2>/dev/null; then
      if [[ "${EUID}" -eq 0 ]]; then
        systemctl stop packagekit.service 2>/dev/null && ok "Stopped packagekit.service" || warn "Could not stop packagekit.service"
      elif sudo -n systemctl stop packagekit.service 2>/dev/null; then
        ok "Stopped packagekit.service"
      else
        warn "packagekit.service active — run: sudo systemctl stop packagekit.service"
      fi
    fi
  fi
  local proc
  for proc in dnfdragora dnf5daemon; do
    if pgrep -x "${proc}" >/dev/null 2>&1; then
      pkill -x "${proc}" 2>/dev/null && ok "Stopped ${proc}" || warn "Could not stop ${proc}"
    fi
  done
  if pgrep -x dnf >/dev/null 2>&1; then
    warn "dnf is running — wait for it to finish or close the owning terminal"
  fi
  if pgrep -x rpm >/dev/null 2>&1; then
    warn "rpm is running — wait for it to finish"
  fi
}

# ---------- GPU / nouveau ----------
readiness_nouveau_warning_count() {
  local count=0
  if have journalctl; then
    count="$(journalctl -b -k --no-pager 2>/dev/null | grep -ci nouveau || true)"
  elif [[ -r /var/log/messages ]]; then
    count="$(grep -ci nouveau /var/log/messages 2>/dev/null || true)"
  fi
  printf '%s\n' "${count:-0}"
}

# ---------- disk mounts for daily driver ----------
readiness_key_mount_lines() {
  local mount line
  for mount in / /home /boot /boot/efi /data /var/lib/mysql; do
    if df -hT "${mount}" >/dev/null 2>&1; then
      df -hT "${mount}" | awk -v m="${mount}" 'NR==2 {printf "  %-16s %s total · %s used · %s free · %s [%s]\n", m, $3, $4, $5, $6, $2}'
    fi
  done
}

# ---------- post-update ----------
# needs-restarting -r: exit 0 = no reboot, exit 1 = reboot required (dnf man page).
_READINESS_NR_OUT=""
_READINESS_NR_EC=""

readiness_needs_restarting_probe() {
  [[ -n "${_READINESS_NR_PROBED:-}" ]] && return 0
  if have needs-restarting; then
    _READINESS_NR_OUT="$(needs-restarting -r 2>&1)" || _READINESS_NR_EC=$?
    _READINESS_NR_EC="${_READINESS_NR_EC:-0}"
  fi
  _READINESS_NR_PROBED=1
}

# Returns 0 when a reboot is recommended, 1 when not.
readiness_reboot_needed() {
  local running latest
  running="$(uname -r)"
  latest="$(readiness_latest_installed_kernel)"
  if [[ -n "${latest}" && "${running}" != "${latest}" ]]; then
    return 0
  fi
  readiness_needs_restarting_probe
  if have needs-restarting; then
    if [[ "${_READINESS_NR_OUT}" == *"Config error"* ]] || [[ "${_READINESS_NR_OUT}" == *"Permission denied"* ]]; then
      return 1
    fi
    if [[ "${_READINESS_NR_OUT}" == *"Reboot should not be necessary"* ]] || (( _READINESS_NR_EC == 0 )); then
      return 1
    fi
    return 0
  fi
  if [[ -f /var/run/reboot-required ]]; then
    return 0
  fi
  return 1
}

# Human-readable needs-restarting output for reports (may be empty on tool errors).
readiness_reboot_status_text() {
  local running latest
  running="$(uname -r)"
  latest="$(readiness_latest_installed_kernel)"
  if [[ -n "${latest}" && "${running}" != "${latest}" ]]; then
    printf 'running %s · newest installed %s\n' "${running}" "${latest}"
    return 0
  fi
  readiness_needs_restarting_probe
  if ! have needs-restarting; then
    return 0
  fi
  if [[ "${_READINESS_NR_OUT}" == *"Config error"* ]] || [[ "${_READINESS_NR_OUT}" == *"Permission denied"* ]]; then
    printf 'needs-restarting unavailable (run as user with dnf log access)\n'
    return 0
  fi
  printf '%s\n' "${_READINESS_NR_OUT}"
}

# ---------- reports ----------
readiness_print_section() {
  theme_section "$1"
}

readiness_print_daily_driver() {
  local host model os kernel boot failed bootline stats scrub keyslots cmdline nouveau
  local vbox_ver

  theme_set_lane audit
  theme_report_header "Daily driver check" \
    "HOST / $(health_hostname) · USER / $(real_user)" \
    "Read-only workstation readiness (Fedora control plane)"

  readiness_print_section "System"
  host="$(health_hostname)"
  model="$(readiness_host_model)"
  os="$(health_os_pretty)"
  kernel="$(health_kernel)"
  theme_kv "Hostname" "${host}"
  theme_kv "Model" "${model}"
  theme_kv "OS" "${os}"
  theme_kv "Kernel" "${kernel}"

  readiness_print_section "Boot"
  boot="$(readiness_boot_time_summary || true)"
  theme_kv "Boot time" "${boot:-unknown}"
  if have systemd-analyze; then
    theme_note "Slow boot tip: LUKS unlock retries in initrd often dominate — not userspace."
    while IFS= read -r bootline; do
      [[ -n "${bootline}" ]] && theme_kv " blame" "${bootline}"
    done < <(readiness_boot_blame_top 3)
  fi
  cmdline="$(readiness_kernel_cmdline)"
  theme_kv "Kernel cmdline" "${cmdline}"
  if readiness_kernel_has_rhgb_quiet; then
    theme_kv "rhgb quiet" "present (LUKS prompt may be hidden)"
  else
    theme_kv "rhgb quiet" "not both present (boot messages visible)"
  fi

  readiness_print_section "Btrfs"
  if readiness_root_is_btrfs; then
    stats="$(readiness_btrfs_device_stats / 2>/dev/null || true)"
    if [[ -n "${stats}" ]]; then
      while IFS= read -r line; do
        [[ -n "${line}" ]] && theme_kv " device stats" "${line}"
      done <<< "${stats}"
    fi
    scrub="$(readiness_btrfs_scrub_status / 2>/dev/null | head -n 8 || true)"
    if [[ -n "${scrub}" ]]; then
      if [[ "${scrub}" == *"requires sudo"* ]]; then
        theme_note "${scrub}"
        theme_note "Run: sudo ./system/system.sh btrfs-health"
      else
        theme_note "Latest scrub:"
        while IFS= read -r line; do
          [[ -n "${line}" ]] && printf '  %s\n' "${line}"
        done <<< "${scrub}"
      fi
    fi
  else
    theme_kv "Root FS" "not btrfs"
  fi

  readiness_print_section "Services"
  failed="$(health_failed_systemd_units_count)"
  theme_kv "Failed units" "${failed}"
  if [[ "${failed}" != "0" ]]; then
    health_failed_systemd_units_list | sed 's/^/  /'
  fi

  readiness_print_section "Memory"
  if read -r _u _t pct avail < <(health_memory_summary 2>/dev/null); then
    theme_kv "RAM" "${_u} / ${_t} (${pct}% used), avail ${avail}"
  fi
  if read -r swap_used swap_total < <(health_swap_summary 2>/dev/null); then
    theme_kv "Swap" "${swap_used} used / ${swap_total} total"
  fi

  readiness_print_section "Disk usage"
  readiness_key_mount_lines

  readiness_print_section "VirtualBox"
  theme_kv "Kernel" "$(uname -r)"
  if readiness_vbox_kernel_matches_running; then
    theme_kv "Kernel match" "running kernel is latest installed"
  else
    theme_kv "Kernel match" "WARN — older kernel booted (vboxdrv may fail)"
  fi
  if [[ -n "$(readiness_vbox_modules_loaded)" ]]; then
    readiness_vbox_modules_loaded | sed 's/^/  /'
  else
    theme_kv "vbox modules" "none loaded"
  fi
  if have systemctl; then
    theme_kv "vboxdrv" "$(service_unit_active vboxdrv.service)"
  fi
  if readiness_vbox_is_installed; then
    if vbox_ver="$(readiness_vbox_version 2>/dev/null)"; then
      theme_kv "VBoxManage" "${vbox_ver}"
    elif vbox_bin="$(cmd_binary_path VBoxManage 2>/dev/null)"; then
      theme_kv "VBoxManage" "installed but version unreadable"
      readiness_vbox_char_dev_ready || theme_note "/dev/vboxdrv missing — VMs cannot start until vboxdrv is loaded"
    else
      theme_kv "VBoxManage" "package installed but binary not on PATH"
    fi
    if [[ -n "$(readiness_vbox_modules_loaded)" ]] && ! readiness_vbox_char_dev_ready; then
      theme_note "vbox modules in lsmod but /dev/vboxdrv missing — try: sudo systemctl restart vboxdrv.service"
    fi
  else
    theme_kv "VirtualBox" "not installed"
  fi

  readiness_print_section "Package / update noise"
  if pkg_out="$(readiness_package_noise_list 2>/dev/null)"; then
    printf '%s\n' "${pkg_out}" | sed 's/^/  /'
  else
    theme_kv "Background" "no matching package processes"
  fi

  readiness_print_section "LUKS"
  if dev="$(readiness_luks_root_device 2>/dev/null)"; then
    theme_kv "LUKS device" "${dev}"
    if mapper="$(readiness_luks_mapper_device 2>/dev/null)"; then
      theme_kv "Mapper" "${mapper}"
    fi
    keyslots="$(readiness_luks_keyslot_count 2>/dev/null || echo unknown)"
    theme_kv "Keyslots" "${keyslots}"
    readiness_luks_keyslot_hint "${keyslots}"
    while IFS= read -r path; do
      [[ -n "${path}" ]] || continue
      if [[ -d "${path}" ]] && find "${path}" -maxdepth 2 -type f 2>/dev/null | grep -q .; then
        ok "Header backup dir: ${path}"
      else
        warn "Header backup dir missing or empty: ${path}"
      fi
    done < <(readiness_luks_header_backup_paths)
  else
    theme_kv "Encrypted root" "not detected (or LUKS device unknown)"
  fi

  readiness_print_section "GPU / nouveau"
  nouveau="$(readiness_nouveau_warning_count)"
  theme_kv "nouveau messages (this boot)" "${nouveau}"

  echo
  theme_result_ready "Daily driver check complete"
  theme_meta_line "Next: ./system/system.sh btrfs-health · luks-readiness · post-update-check"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
