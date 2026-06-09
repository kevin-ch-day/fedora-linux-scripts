#!/usr/bin/env bash
# luks_readiness.sh — LUKS encrypted root readiness (read-only by default)
# Version: 0.2.0
#
# Run:
#   ./system/luks_readiness.sh
#   ./system/luks_readiness.sh --add-passphrase   # interactive · sudo
#   ./system/system.sh luks-readiness

set -uo pipefail

_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_ROOT="$(cd -- "${_SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/readiness.sh
source "${FEDORA_ROOT}/lib/readiness.sh"
theme_init
theme_set_lane audit

ADD_PASSPHRASE=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Detect LUKS encrypted root, keyslot count, and header backup presence.
Shows safe backup instructions. Never prints passphrases.

Options:
  --help, -h          Show this help
  --add-passphrase    Add a backup passphrase in a new keyslot (interactive · sudo)
                      Requires header backup (or explicit override confirm).
                      Never removes existing keyslots.

Also: ./system/system.sh luks-readiness [--add-passphrase]

Toolkit root: ${FEDORA_ROOT}
See: docs/RECOVERY.md
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --add-passphrase) ADD_PASSPHRASE=1; shift ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

luks_readiness_report() {
  local ISSUES=0 dev="" backup_ok=0 path cmdline

  theme_report_header "LUKS readiness" \
    "Host: $(health_hostname) · User: $(real_user)" \
    "Read-only · passphrases never displayed"

  theme_section "Encrypted root"
  if dev="$(readiness_luks_root_device 2>/dev/null)"; then
    ok "LUKS device: ${dev}"
    if mapper="$(readiness_luks_mapper_device 2>/dev/null)"; then
      theme_kv "Mapper" "${mapper}"
    fi
    keyslots="$(readiness_luks_keyslot_count 2>/dev/null || echo unknown)"
    theme_kv "Keyslots" "${keyslots}"
    readiness_luks_keyslot_hint "${keyslots}"
  else
    warn "Could not detect LUKS device for /"
    ISSUES=$((ISSUES + 1))
  fi

  theme_section "Header backups"
  backup_ok=0
  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    if [[ -d "${path}" ]] && find "${path}" -maxdepth 2 -type f 2>/dev/null | grep -q .; then
      ok "Backup dir present: ${path}"
      find "${path}" -maxdepth 2 -type f 2>/dev/null | head -n 5 | sed 's/^/  /'
      backup_ok=1
    else
      warn "Missing or empty: ${path}"
      ISSUES=$((ISSUES + 1))
    fi
  done < <(readiness_luks_header_backup_paths)

  theme_section "Safe backup instructions"
  readiness_luks_print_backup_instructions

  theme_section "Boot visibility"
  cmdline="$(readiness_kernel_cmdline)"
  theme_kv "Kernel cmdline" "${cmdline}"
  if readiness_kernel_has_rhgb_quiet; then
    warn "rhgb quiet present — LUKS passphrase prompt may be hidden during boot"
    theme_note "Neptune fix: remove rhgb quiet from kernel cmdline to surface LUKS retries"
  else
    ok "rhgb quiet not both present — boot messages should be visible"
  fi

  echo
  if (( backup_ok == 0 )); then
    theme_summary_box "LUKS summary" "Result: REVIEW" "Header backup dirs missing or empty"
    return 1
  fi
  theme_summary_box "LUKS summary" "Result: OK" "Encrypted root detected · backup path present"
  return 0
}

report_ec=0
luks_readiness_report || report_ec=$?

if (( ADD_PASSPHRASE )); then
  readiness_luks_add_passphrase_interactive
  exit 0
fi

exit "${report_ec}"
