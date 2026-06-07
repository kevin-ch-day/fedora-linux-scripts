#!/usr/bin/env bash
# lib/entry_points.sh — shared launcher layout checks (validate.sh + Fedora doctor)
# Version: 0.1.1
#
# Source after lib/common.sh:
#   fedora_entry_points_check ROOT [fail_count_var]
#
# Optional: FEDORA_ENTRY_POINTS_BANNER=1 prints section header (doctor UI).

if [[ -n "${FEDORA_ENTRY_POINTS_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_ENTRY_POINTS_SH_LOADED=1

# fedora_entry_points_check ROOT [fail_count_varname]
# Prints [OK]/[WARN] per check. Returns 0 if all pass, 1 otherwise.
# If fail_count_varname is set, increments that variable per failed check.
fedora_entry_points_check() {
  local fedora_root="${1:?fedora root required}"
  local fail_var="${2:-}"
  local rc=0
  local path
  local n=0

  if [[ "${FEDORA_ENTRY_POINTS_BANNER:-0}" == 1 ]]; then
    common_init_colors
    theme_section "Entry points"
  fi

  for path in fedora.sh mobsf.sh fedora_rebuild.sh validate.sh smoke_test.sh; do
    if [[ -x "${fedora_root}/${path}" ]]; then
      ok "./${path}"
    else
      warn "Missing or not executable: ./${path}"
      rc=1
      n=$((n + 1))
    fi
  done

  if [[ -x "${fedora_root}/mobsf/mobsf.sh" ]]; then
    ok "./mobsf/mobsf.sh (MobSF implementation)"
  else
    warn "Missing or not executable: ./mobsf/mobsf.sh"
    rc=1
    n=$((n + 1))
  fi

  if grep -qE '_fedora_open_lane.*mobsf|menu_item [0-9]+ "MobSF lane' "${fedora_root}/fedora.sh" 2>/dev/null; then
    warn "fedora.sh still references MobSF as an active lane (expected separate ./mobsf.sh only)"
    rc=1
    n=$((n + 1))
  else
    ok "fedora.sh — MobSF not listed as an active lane"
  fi

  if [[ -n "${fail_var}" ]]; then
    # shellcheck disable=SC2154
    printf -v "${fail_var}" '%s' "${n}"
  fi

  return "${rc}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
