#!/usr/bin/env bash
# lib/profiles.sh — named install / rebuild profiles (step lists)
# Version: 0.2.0
#
# Profiles are consumed by lib/install_engine.sh, install.sh, fedora_rebuild.sh.
# Do not execute directly.

if [[ -n "${FEDORA_PROFILES_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
FEDORA_PROFILES_SH_LOADED=1

_PROFILES_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${_PROFILES_LIB_DIR}/common.sh"

# profile_list_names — one profile id per line
profile_list_names() {
  printf '%s\n' research android-re dev-stack dev-full web-stack mobsf daily-sync update-only
}

profile_is_valid() {
  local want="$1" p
  for p in $(profile_list_names); do
    [[ "${p}" == "${want}" ]] && return 0
  done
  return 1
}

profile_description() {
  case "${1:-}" in
    research)
      printf '%s\n' "Full research workstation — update, KVM, Android core, RE tools, optional MobSF"
      ;;
    android-re)
      printf '%s\n' "Android RE stack — core packages, apktool/jadx/smali/dex2jar, verify"
      ;;
    dev-stack)
      printf '%s\n' "Developer stack — VS Code, containers, KVM/libvirt"
      ;;
    dev-full)
      printf '%s\n' "Developer workstation — git (if needed), VS Code, containers, KVM"
      ;;
    web-stack)
      printf '%s\n' "Web/database — Apache, MariaDB, PHP, phpMyAdmin"
      ;;
    mobsf)
      printf '%s\n' "MobSF static analysis stack — Podman compose install + doctor"
      ;;
    daily-sync)
      printf '%s\n' "Daily driver — full Fedora update + post-update check"
      ;;
    update-only)
      printf '%s\n' "Fedora update only (dnf upgrade, no post-update check)"
      ;;
    *)
      printf '%s\n' "unknown profile"
      return 1
      ;;
  esac
}

# profile_wants_mobsf PROFILE — 0 yes offer MobSF step
profile_wants_mobsf() {
  case "${1:-}" in
    research) return 0 ;;
    *) return 1 ;;
  esac
}

# profile_wants_doctor PROFILE — 0 yes offer research doctor at end
profile_wants_doctor() {
  case "${1:-}" in
    research|android-re|mobsf|web-stack) return 0 ;;
    *) return 1 ;;
  esac
}

# profile_doctor_script PROFILE — relative path under toolkit root
profile_doctor_script() {
  case "${1:-}" in
    research) printf '%s\n' "system/research_doctor.sh" ;;
    android-re) printf '%s\n' "android/doctor_android_research.sh" ;;
    mobsf) printf '%s\n' "mobsf/mobsf_doctor.sh" ;;
    web-stack) printf '%s\n' "dev/web_stack_doctor.sh" ;;
    *) return 1 ;;
  esac
}

# profile_iter_steps PROFILE
# Emits TSV rows: title \t rel_script \t sudo_mode \t extra_args
# sudo_mode: none | sudo | sudo-E
profile_iter_steps() {
  local profile="${1:?profile required}"
  case "${profile}" in
    research)
      printf '%s\n' $'System update\tsystem/system_update.sh\tsudo-E\t--quick'
      ;;
    daily-sync|update-only)
      printf '%s\n' $'System update\tsystem/system_update.sh\tsudo-E\t'
      ;;
  esac
  case "${profile}" in
    research|daily-sync)
      printf '%s\n' $'Post-update check\tsystem/post_update_check.sh\tnone\t'
      ;;
  esac
  case "${profile}" in
    research)
      printf '%s\n' $'Containers + KVM\tdev/fedora_container_kvm_setup.sh\tsudo\t'
      printf '%s\n' $'Android core tools\tandroid/android_dev_core_setup.sh\tsudo\t'
      printf '%s\n' $'Install RE tools (all)\tandroid/android_re_install.sh\tnone\tall'
      printf '%s\n' $'Verify all RE tools\tandroid/verify_re_tool.sh\tnone\tall'
      ;;
    android-re)
      printf '%s\n' $'Android core tools\tandroid/android_dev_core_setup.sh\tsudo\t'
      printf '%s\n' $'Install RE tools (all)\tandroid/android_re_install.sh\tnone\tall'
      printf '%s\n' $'Verify all RE tools\tandroid/verify_re_tool.sh\tnone\tall'
      ;;
    dev-stack)
      printf '%s\n' $'Install VS Code\tdev/install_vscode.sh\tsudo\t'
      printf '%s\n' $'Containers + KVM\tdev/fedora_container_kvm_setup.sh\tsudo\t'
      ;;
    dev-full)
      printf '%s\n' $'Git identity (if needed)\tdev/git_setup.sh\tnone\t--skip-if-configured'
      printf '%s\n' $'Install VS Code\tdev/install_vscode.sh\tsudo\t'
      printf '%s\n' $'Containers + KVM\tdev/fedora_container_kvm_setup.sh\tsudo\t'
      ;;
    web-stack)
      printf '%s\n' $'Apache + MariaDB + PHP\tdev/lamp_python_setup.sh\tsudo\t'
      printf '%s\n' $'phpMyAdmin\tdev/phpmyadmin_setup.sh\tsudo\t'
      ;;
    mobsf)
      printf '%s\n' $'MobSF install\tmobsf/mobsf_install.sh\tsudo-E\t'
      ;;
  esac
}

profile_step_count() {
  local profile="${1:?profile required}"
  local n=0
  while IFS= read -r _; do
    [[ -n "${_}" ]] && n=$((n + 1))
  done < <(profile_iter_steps "${profile}")
  printf '%s\n' "${n}"
}

profile_print_catalog() {
  local p desc
  theme_section "Install profiles"
  for p in $(profile_list_names); do
    desc="$(profile_description "${p}")"
    theme_note_kv "${p}" "${desc}"
  done
  theme_note "Run: ./install.sh <profile> [--yes] [--dry-run] [--plan]"
  theme_note "Plan: ./install.sh <profile> --plan   ·   ./run.sh --profile <name> --dry-run"
}

# profile_validate_steps ROOT — returns 0 if all step scripts exist
profile_validate_steps() {
  local root="${1:?root required}"
  local profile="${2:?profile required}"
  local title rel sudo_mode args_line missing=0

  profile_is_valid "${profile}" || return 1

  while IFS=$'\t' read -r title rel sudo_mode args_line; do
    [[ -n "${title}" ]] || continue
    if [[ ! -f "${root}/${rel}" ]]; then
      warn "profile ${profile}: missing step script ${rel} (${title})"
      missing=$((missing + 1))
    fi
  done < <(profile_iter_steps "${profile}")

  if profile_wants_mobsf "${profile}"; then
    [[ -f "${root}/mobsf/mobsf_install.sh" ]] || {
      warn "profile ${profile}: missing optional MobSF script mobsf/mobsf_install.sh"
      missing=$((missing + 1))
    }
  fi

  if profile_wants_doctor "${profile}"; then
    local doc=""
    if doc="$(profile_doctor_script "${profile}")" && [[ ! -f "${root}/${doc}" ]]; then
      warn "profile ${profile}: missing doctor script ${doc}"
      missing=$((missing + 1))
    fi
  fi

  return $(( missing > 0 ? 1 : 0 ))
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  err "Source this file; do not execute directly."
  exit 1
fi
