#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Filename: system_update.sh
# Purpose : Fedora system update + cleanup (deterministic, ops-grade)
# Version : 0.7.0
#
# Run:
#   sudo ./system/system_update.sh
#   sudo ./system/system_update.sh --quick
#   sudo ./system/system_update.sh --help
#
# Logging:
#   Engine: lib/logging.sh — logs/system_update.log
#   Env: FEDORA_LOG_LEVEL=DEBUG  FEDORA_LOG_ROTATE_MB=10 (default: 10)
# ============================================================

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${_SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/packages.sh
source "${_SCRIPT_DIR}/../lib/packages.sh"
# shellcheck source=../lib/health.sh
source "${_SCRIPT_DIR}/../lib/health.sh"
# shellcheck source=../lib/logging.sh
source "${_SCRIPT_DIR}/../lib/logging.sh"
# shellcheck source=../lib/theme.sh
source "${_SCRIPT_DIR}/../lib/theme.sh"

QUICK=0
UPDATE_ISSUES=0
QUIET_TERMINAL=1
TEST_MODE="${FEDORA_UPDATE_TEST_MODE:-0}"
UPDATE_COUNT=0
declare -a UPDATE_DETAILS=()
LAST_OUTPUT=""
LAST_RC=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Full Fedora update: refresh metadata, upgrade, distro-sync, autoremove,
clean caches, prune old kernels, rpm verify, reboot check, health snapshot.

Always logs to logs/system_update.log (logging engine v0.3).

Options:
  --quick            Skip slow rpm -Va verify (steps 8 still runs health snapshot)
  --help, -h         Show this help

Environment:
  FEDORA_LOG_LEVEL=DEBUG|INFO|WARN|ERROR   (default: INFO)
  FEDORA_LOG_ROTATE_MB=N                   (default: 10, 0=off)

Run with sudo.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --quick) QUICK=1; shift ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
done

if [[ "${FEDORA_VERBOSE:-0}" == 1 ]]; then
  QUIET_TERMINAL=0
fi

if (( QUIET_TERMINAL )); then
  exec 3>&1 4>&2
  export FEDORA_LOG_TERMINAL_BANNER=0
  export FEDORA_LOG_TERMINAL_STRUCTURED=0
fi

ui_line() {
  if (( QUIET_TERMINAL )); then
    printf '%s\n' "$*" >&3
  else
    printf '%s\n' "$*"
  fi
}

ui_blank() {
  ui_line ""
}

ui_rule() {
  local char="$1"
  local width="${2:-54}"
  local line=""
  printf -v line '%*s' "${width}" ''
  line="${line// /${char}}"
  ui_line "${line}"
}

ui_status() {
  local level="$1"
  shift
  ui_line "$(printf '%-8s %s' "[${level}]" "$*")"
}

ui_ok() { ui_status "OK" "$*"; }
ui_warn() { ui_status "WARN" "$*"; }
ui_fail() { ui_status "FAIL" "$*"; }
ui_note() { ui_status "INFO" "$*"; }

ui_detail() {
  ui_line "     $*"
}

ui_section() {
  ui_blank
  ui_line "[$1]"
}

ui_header() {
  ui_rule '═'
  ui_line "UPD / Fedora update"
  ui_rule '─'
  ui_line "HOST / $(hostname)"
  ui_line "LOG / logs/${FEDORA_LOG_SYSTEM_UPDATE}"
  ui_rule '─'
}

run_logged() {
  local rc
  set +e
  if (( QUIET_TERMINAL )); then
    "$@" >> "${LOG_FILE}" 2>&1
  else
    "$@"
  fi
  rc=$?
  set -e
  return "${rc}"
}

run_logged_capture() {
  local tmp rc
  tmp="$(mktemp)"
  set +e
  if (( QUIET_TERMINAL )); then
    "$@" 2>&1 | tee -a "${LOG_FILE}" > "${tmp}"
    rc=${PIPESTATUS[0]}
  else
    "$@" 2>&1 | tee "${tmp}"
    rc=${PIPESTATUS[0]}
  fi
  set -e
  LAST_OUTPUT="$(cat "${tmp}")"
  LAST_RC="${rc}"
  rm -f "${tmp}"
  return "${rc}"
}

dir_size_bytes() {
  local path="$1"
  du -sb "${path}" 2>/dev/null | awk '{print $1}' || echo 0
}

format_bytes_human() {
  local bytes="${1:-0}"
  if have numfmt; then
    numfmt --to=iec --suffix=B "${bytes}"
  else
    printf '%s B\n' "${bytes}"
  fi
}

fedora_release_short() {
  sed -E 's/^Fedora release ([0-9]+).*/Fedora \1/' /etc/fedora-release 2>/dev/null || echo "Fedora unknown"
}

parse_update_rows() {
  local line pkg_full pkg_name target_ver current_ver
  UPDATE_COUNT=0
  UPDATE_DETAILS=()
  while IFS= read -r line; do
    [[ "${line}" =~ ^[[:alnum:]_.+-]+[[:space:]]+[[:alnum:]_.:+~^-]+[[:space:]] ]] || continue
    pkg_full="$(awk '{print $1}' <<< "${line}")"
    target_ver="$(awk '{print $2}' <<< "${line}")"
    pkg_name="${pkg_full%.*}"
    current_ver="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' "${pkg_name}" 2>/dev/null | head -n 1 || true)"
    ((UPDATE_COUNT += 1))
    if (( ${#UPDATE_DETAILS[@]} < 5 )); then
      if [[ -n "${current_ver}" ]]; then
        UPDATE_DETAILS+=("${pkg_name} ${current_ver} → ${target_ver}")
      else
        UPDATE_DETAILS+=("${pkg_name} → ${target_ver}")
      fi
    fi
  done <<< "${LAST_OUTPUT}"
}

summarize_action_output() {
  local action_name="$1"
  local nothing_label="$2"
  if grep -qi "Nothing to do" <<< "${LAST_OUTPUT}"; then
    ui_ok "${action_name}: ${nothing_label}"
  else
    ui_ok "${action_name}: completed"
    ui_detail "Log contains full transaction details"
  fi
}

summarize_reboot() {
  local running newest failed_units
  running="$(uname -r)"
  newest=""
  if have rpm; then
    newest="$(rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V | tail -n 1 || true)"
  fi

  ui_section "Reboot"
  if [[ -n "${newest}" ]] && [[ "${running}" != "${newest}" ]]; then
    ui_warn "Reboot recommended"
    ui_detail "running ${running} · newest installed ${newest}"
  elif have needs-restarting; then
    if needs-restarting -r >/dev/null 2>&1; then
      ui_ok "No reboot required"
    else
      ui_warn "Reboot recommended"
      ui_detail "needs-restarting reported a reboot requirement"
    fi
  else
    ui_ok "No reboot required"
    ui_note "Install dnf-plugins-core for stronger needs-restarting checks"
  fi
}

summarize_health() {
  local root_pct failed_units
  root_pct="$(health_root_disk_pct)"
  failed_units="$(health_failed_systemd_units_count)"
  ui_section "Health"
  ui_ok "/ root usage: ${root_pct}%"
  ui_ok "failed systemd units: ${failed_units}"
}

offer_post_update_check() {
  local user ans
  ui_section "Next"
  ui_line "ACTION / ./run.sh --post-update-check  (or main menu [3])"
  if (( TEST_MODE )); then
    return 0
  fi
  [[ -r /dev/tty && -w /dev/tty ]] || return 0
  printf 'Run post-update readiness check now? [y/N] ' >/dev/tty
  IFS= read -r ans </dev/tty || return 0
  case "${ans,,}" in
    y|yes)
      user="$(real_user)"
      if [[ "${EUID}" -eq 0 && "${user}" != root ]]; then
        sudo -u "${user}" -H bash "${FEDORA_ROOT}/system/post_update_check.sh" >&3 2>&4 || true
      else
        bash "${FEDORA_ROOT}/system/post_update_check.sh" >&3 2>&4 || true
      fi
      ;;
  esac
}

if (( TEST_MODE )); then
  require_root() { return 0; }
  packages_preflight() {
    echo "[preflight] Fedora release: Fedora release 44 (Forty Four)"
    echo "[preflight] Kernel         : 7.0.11-200.fc44.x86_64"
    echo
  }
  wait_for_dnf_lock() {
    echo "[lock] No active package manager detected."
  }
  dnf_makecache_refresh() {
    cat <<'EOF'
Updating and loading repositories:
repo fedora 100% | test
Metadata cache created.
EOF
  }
  dnf_show_updates() {
    cat <<'EOF'
kf6-ktexteditor.x86_64 6.26.0-2.fc44 updates
EOF
    return 100
  }
  dnf_upgrade() {
    cat <<'EOF'
Upgrading:
 kf6-ktexteditor x86_64 6.26.0-2.fc44 updates
Complete!
EOF
  }
  dnf_distro_sync() { echo "Nothing to do."; }
  dnf_autoremove() { echo "Nothing to do."; }
  dnf_clean_all() { echo "5 files removed"; }
  kernel_prune_keep3() { echo "No old kernels to remove (installed: 2)."; }
  rpm_verify_report() { echo "No verification deltas detected."; }
  dnf_check() { echo "Dependencies resolved."; }
  health_post_update_snapshot() {
    echo "Quick health snapshot:"
    echo "  Disk usage:"
    echo "   - /: 11% used"
    echo "  Failed systemd units: 0"
  }
  health_root_disk_pct() { echo 11; }
  health_failed_systemd_units_count() { echo 0; }
  rpm() {
    if [[ "${1:-}" == "-q" && "${2:-}" == "--qf" ]]; then
      case "${4:-}" in
        kf6-ktexteditor) echo "6.26.0-1.fc44.x86_64" ;;
        kernel) echo "7.0.11-200.fc44.x86_64" ;;
      esac
      return 0
    fi
    command rpm "$@"
  }
fi

if (( TEST_MODE == 0 )); then
  require_root "Run with sudo: sudo ./system/system_update.sh"
fi
FEDORA_LOG_ROTATE_MB="${FEDORA_LOG_ROTATE_MB:-10}"
errors_init_script "system_update.sh"
init_script_logging "${FEDORA_LOG_SYSTEM_UPDATE}" "system_update.sh" "Fedora System Update"
common_init_colors
theme_init
theme_set_lane system

if (( QUIET_TERMINAL )); then
  exec >> "${LOG_FILE}" 2>&1
fi

ui_header

ui_section "Preflight"
if ! run_logged packages_preflight; then
  ui_fail "Preflight checks failed"
  die "packages_preflight failed"
fi
if ! run_logged wait_for_dnf_lock; then
  ui_fail "Active dnf/rpm/PackageKit lock could not be cleared"
  die "wait_for_dnf_lock failed"
fi
ui_ok "$(fedora_release_short)"
ui_ok "Kernel $(uname -r)"
ui_ok "No active dnf/rpm/PackageKit lock"

ui_section "Update"
if ! run_logged_capture dnf_makecache_refresh; then
  ui_fail "Metadata refresh failed"
  die "dnf makecache failed"
fi
ui_ok "Metadata refreshed"

if run_logged_capture dnf_show_updates; then
  parse_update_rows
elif [[ "${LAST_RC}" -eq 100 ]]; then
  parse_update_rows
else
  ui_fail "Could not query available updates"
  die "dnf check-update failed"
fi

if (( UPDATE_COUNT > 0 )); then
  ui_note "Applying package upgrades; this can take several minutes"
  ui_detail "Full transaction output is being written to ${LOG_FILE}"
fi
if ! run_logged_capture dnf_upgrade; then
  ui_fail "Fedora upgrade failed"
  die "dnf upgrade failed"
fi
if (( UPDATE_COUNT == 0 )); then
  ui_ok "No package upgrades needed"
else
  if (( UPDATE_COUNT == 1 )); then
    ui_ok "1 package upgraded"
  else
    ui_ok "${UPDATE_COUNT} packages upgraded"
  fi
  for detail in "${UPDATE_DETAILS[@]}"; do
    ui_detail "${detail}"
  done
  if (( UPDATE_COUNT > ${#UPDATE_DETAILS[@]} )); then
    ui_detail "Log contains full transaction details"
  fi
fi

ui_section "Maintenance"
ui_note "Running post-upgrade maintenance"
if run_logged_capture dnf_distro_sync; then
  summarize_action_output "distro-sync" "nothing to do"
else
  ui_warn "distro-sync reported issues"
  ui_detail "Review ${LOG_FILE}"
  UPDATE_ISSUES=$((UPDATE_ISSUES + 1))
fi

if ! run_logged_capture dnf_autoremove; then
  ui_fail "autoremove failed"
  die "dnf autoremove failed"
fi
summarize_action_output "autoremove" "nothing to do"

cache_before="$(dir_size_bytes /var/cache/dnf)"
if ! run_logged_capture dnf_clean_all; then
  ui_fail "DNF cache clean failed"
  die "dnf clean failed"
fi
cache_after="$(dir_size_bytes /var/cache/dnf)"
cache_removed=$(( cache_before > cache_after ? cache_before - cache_after : 0 ))
ui_ok "DNF cache cleaned: $(format_bytes_human "${cache_removed}") removed"

kernel_before_count="$(rpm_installed_kernels | sed '/^$/d' | wc -l | tr -d ' ')"
if ! run_logged_capture kernel_prune_keep3; then
  ui_warn "old kernel pruning reported issues"
  ui_detail "Review ${LOG_FILE}"
  UPDATE_ISSUES=$((UPDATE_ISSUES + 1))
else
  kernel_after_count="$(rpm_installed_kernels | sed '/^$/d' | wc -l | tr -d ' ')"
  kernel_removed=$(( kernel_before_count > kernel_after_count ? kernel_before_count - kernel_after_count : 0 ))
  if (( kernel_removed == 0 )); then
    ui_ok "old kernels: none removed, ${kernel_after_count} installed"
  else
    ui_ok "old kernels: ${kernel_removed} removed, ${kernel_after_count} installed"
  fi
fi

if (( QUICK )); then
  log_info "Skipped rpm -Va (--quick)"
else
  run_logged rpm_verify_report 200 180 || true
fi

if run_logged_capture dnf_check; then
  ui_ok "dependency check passed"
else
  ui_warn "dependency check reported issues"
  ui_detail "Review ${LOG_FILE}"
  UPDATE_ISSUES=$((UPDATE_ISSUES + 1))
fi

run_logged health_post_update_snapshot || true
summarize_health
summarize_reboot

run_logged packages_fix_repo_permissions || true

ui_section "Status"
if (( UPDATE_ISSUES == 0 )); then
  log_info "Update run complete — no soft-fail steps"
  ui_ok "Fedora update completed successfully"
else
  log_warn "Update run complete — ${UPDATE_ISSUES} soft-fail step(s); see log above"
  ui_warn "Fedora update completed with ${UPDATE_ISSUES} issue(s)"
fi
ui_line "LOG / ${LOG_FILE}"
offer_post_update_check

exit $(( UPDATE_ISSUES > 0 ? 1 : 0 ))
