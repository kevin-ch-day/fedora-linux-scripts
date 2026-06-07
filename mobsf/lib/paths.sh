#!/usr/bin/env bash
# mobsf/lib/paths.sh — MobSF path resolution
# Do not execute directly.

mobsf_home_dir() {
  printf '%s/MobSF\n' "$(real_home)"
}

mobsf_data_dir() {
  printf '%s/mobsf_data\n' "$(mobsf_home_dir)"
}

mobsf_pg_dir() {
  printf '%s/postgresql_data\n' "$(mobsf_home_dir)"
}

mobsf_default_compose_dir() {
  printf '%s/compose\n' "$(mobsf_home_dir)"
}

mobsf_legacy_compose_dir() {
  printf '%s/Downloads/MobSF/docker\n' "$(real_home)"
}

# Resolve compose dir: env > ~/MobSF/compose > legacy Downloads path
mobsf_compose_dir() {
  local dir="${MOBSF_COMPOSE_DIR:-}"
  if [[ -n "${dir}" && -f "${dir}/docker-compose.yml" ]]; then
    printf '%s\n' "${dir}"
    return 0
  fi
  dir="$(mobsf_default_compose_dir)"
  if [[ -f "${dir}/docker-compose.yml" ]]; then
    printf '%s\n' "${dir}"
    return 0
  fi
  dir="$(mobsf_legacy_compose_dir)"
  if [[ -f "${dir}/docker-compose.yml" ]]; then
    printf '%s\n' "${dir}"
    return 0
  fi
  printf '%s\n' "$(mobsf_default_compose_dir)"
}

mobsf_compose_file() {
  printf '%s/docker-compose.yml\n' "$(mobsf_compose_dir)"
}

mobsf_init_paths() {
  # shellcheck disable=SC2034
  MOBSF_HOME="$(mobsf_home_dir)"
  MOBSF_DATA_DIR="$(mobsf_data_dir)"
  MOBSF_PG_DIR="$(mobsf_pg_dir)"
  MOBSF_COMPOSE_DIR_RESOLVED="$(mobsf_compose_dir)"
  MOBSF_COMPOSE_FILE="${MOBSF_COMPOSE_DIR_RESOLVED}/docker-compose.yml"
}

mobsf_compose_installed() {
  [[ -f "$(mobsf_compose_file)" ]]
}

mobsf_compose_cd() {
  mobsf_init_paths
  [[ -d "${MOBSF_COMPOSE_DIR_RESOLVED}" ]] || return 1
  [[ -f "${MOBSF_COMPOSE_FILE}" ]] || return 1
  cd "${MOBSF_COMPOSE_DIR_RESOLVED}" || return 1
}

mobsf_prepare_data_dirs() {
  local mode="${1:-keep}"
  local perm="${MOBSF_DATA_DIR_MODE:-0770}"
  local user group
  mobsf_init_paths
  user="$(real_user)"
  group="$(id -gn "${user}" 2>/dev/null || echo "${user}")"

  if [[ "${perm}" == "0777" || "${perm}" == "777" ]]; then
    warn "MOBSF_DATA_DIR_MODE=${perm} is world-writable — use only for debugging container write issues"
  fi

  if [[ "${mode}" == "nuke" ]]; then
    info "Removing MobSF data dirs (nuke)"
    rm -rf "${MOBSF_DATA_DIR}" "${MOBSF_PG_DIR}"
  fi
  run_as_real_user mkdir -p "${MOBSF_DATA_DIR}" "${MOBSF_PG_DIR}"
  if have chcon && [[ "$(getenforce 2>/dev/null || echo Disabled)" != "Disabled" ]]; then
    chcon -Rt container_file_t "${MOBSF_DATA_DIR}" "${MOBSF_PG_DIR}" 2>/dev/null || true
  fi
  chown -R "${user}:${group}" "${MOBSF_DATA_DIR}" "${MOBSF_PG_DIR}" 2>/dev/null || true
  chmod -R "${perm}" "${MOBSF_DATA_DIR}" "${MOBSF_PG_DIR}" 2>/dev/null || true
  ok "MobSF data dirs: ${user}:${group} mode ${perm}"
}
