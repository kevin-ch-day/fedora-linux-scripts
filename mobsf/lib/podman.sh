#!/usr/bin/env bash
# mobsf/lib/podman.sh — rootless Podman helpers for MobSF
# Do not execute directly.

mobsf_pc() {
  run_as_real_user podman-compose "$@"
}

mobsf_pd() {
  run_as_real_user podman "$@"
}

mobsf_require_tools() {
  need_cmd podman
  need_cmd podman-compose
  have curl || warn "curl not found — HTTP checks may fail"
}

mobsf_require_tools_root_ops() {
  mobsf_require_tools
  have chcon || warn "chcon not found — SELinux labeling skipped"
}

mobsf_container_for_service() {
  local svc="$1"
  mobsf_pd ps -a \
    --filter "label=io.podman.compose.service=${svc}" \
    --format "{{.Names}}" 2>/dev/null | head -n 1
}

mobsf_container_exists() {
  local name="$1"
  [[ -n "${name}" ]] || return 1
  mobsf_pd ps -a --format "{{.Names}}" | grep -qx "${name}"
}

mobsf_wait_for_container() {
  local svc="$1"
  local tries="${2:-30}"
  local name=""
  local i
  for ((i=1; i<=tries; i++)); do
    name="$(mobsf_container_for_service "${svc}")"
    if [[ -n "${name}" ]] && mobsf_container_exists "${name}"; then
      printf '%s\n' "${name}"
      return 0
    fi
    sleep 1
  done
  return 1
}

mobsf_check_ui_http() {
  local code
  have curl || { warn "curl missing — skipping UI check"; return 0; }
  code="$(curl -sS -o /dev/null -w "%{http_code}" "${MOBSF_LOGIN_URL}" 2>/dev/null)" || code="000"
  info "HTTP ${MOBSF_LOGIN_URL} → ${code}"
  [[ "${code}" == "200" || "${code}" == "301" || "${code}" == "302" ]]
}

mobsf_show_status() {
  mobsf_init_paths
  echo "MobSF stack status (user=$(real_user))"
  echo "  Compose : ${MOBSF_COMPOSE_DIR_RESOLVED}"
  echo "  UI      : ${MOBSF_UI_URL}"
  echo
  if ! cmd_available podman; then
    err "podman not installed"
    return 1
  fi
  mobsf_pd ps -a --filter "label=io.podman.compose.project" \
    --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null \
    || mobsf_pd ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# Remove MobSF compose containers only (scoped by project working_dir under ~/MobSF).
mobsf_cleanup_orphans() {
  local legacy cid wd name
  local -a ids=() seen=()
  local -a services=(postgres nginx mobsf djangoq)

  if ! cmd_available podman; then
    warn "podman not installed — nothing to clean"
    return 0
  fi

  mobsf_init_paths
  legacy="$(mobsf_legacy_compose_dir)"

  for svc in "${services[@]}"; do
    while IFS= read -r cid; do
      [[ -n "${cid}" ]] || continue
      if ((${#seen[@]} > 0)) && printf '%s\n' "${seen[@]}" | grep -qx "${cid}"; then
        continue
      fi
      wd="$(mobsf_pd inspect "${cid}" --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' 2>/dev/null || true)"
      if [[ -z "${wd}" ]]; then
        name="$(mobsf_pd inspect "${cid}" --format '{{.Name}}' 2>/dev/null || echo "${cid}")"
        warn "Skipping ${name}: no compose working_dir label"
        continue
      fi
      if [[ "${wd}" == "${MOBSF_HOME}"* ]] || [[ "${wd}" == "${legacy}" ]]; then
        ids+=("${cid}")
        seen+=("${cid}")
      else
        name="$(mobsf_pd inspect "${cid}" --format '{{.Name}}' 2>/dev/null || echo "${cid}")"
        warn "Skipping non-MobSF compose container: ${name} (${wd})"
      fi
    done < <(mobsf_pd ps -aq --filter "label=io.podman.compose.service=${svc}" 2>/dev/null || true)
  done

  if ((${#ids[@]} == 0)); then
    ok "No MobSF compose containers to remove"
    return 0
  fi
  info "Removing ${#ids[@]} MobSF compose container(s)..."
  mobsf_pd rm -f "${ids[@]}" 2>/dev/null || true
  ok "Removed ${#ids[@]} container(s)"
}
