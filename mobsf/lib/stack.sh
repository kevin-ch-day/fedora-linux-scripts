#!/usr/bin/env bash
# mobsf/lib/stack.sh — MobSF stack lifecycle (up, down, reset, install)
# Do not execute directly.

mobsf_stack_down() {
  mobsf_compose_cd || die_with_hint "Compose dir not found" "Run: sudo -E ./mobsf/mobsf_install.sh"
  info "Stopping MobSF stack..."
  mobsf_pc_action "MobSF stack stop" down --remove-orphans || true
}

mobsf_stack_pull() {
  mobsf_compose_cd || die_with_hint "Compose dir not found" "Run: sudo -E ./mobsf/mobsf_install.sh"
  info "Pulling container images..."
  require_ok "MobSF image pull failed" mobsf_pc_action "MobSF image pull" pull
}

mobsf_wait_postgres() {
  local pg_name tries=60 i
  pg_name="$(mobsf_wait_for_container postgres 30)" || die_with_hint \
    "postgres container did not appear" "Run: ./mobsf/mobsf_doctor.sh"
  info "Waiting for postgres readiness (${pg_name})..."
  for ((i=1; i<=tries; i++)); do
    if mobsf_pd exec "${pg_name}" pg_isready -h 127.0.0.1 -p 5432 -U postgres -d mobsf >/dev/null 2>&1; then
      ok "postgres ready"
      printf '%s\n' "${pg_name}"
      return 0
    fi
    if (( i == tries )); then
      mobsf_pd logs --tail=200 "${pg_name}" || true
      die_with_hint "postgres did not become ready" \
        "Check logs above; try: sudo -E ./mobsf/mobsf_reset.sh --keep"
    fi
    sleep 2
  done
}

mobsf_wait_mobsf_internal() {
  local mobsf_name tries=120 i
  local ready_cmd='curl -fsS http://127.0.0.1:8000/login/ >/dev/null 2>&1 || wget -qO- http://127.0.0.1:8000/login/ >/dev/null 2>&1'
  mobsf_name="$(mobsf_wait_for_container mobsf 60)" || die_with_hint \
    "mobsf container did not appear" "Run: ./mobsf/mobsf_doctor.sh"
  info "Waiting for MobSF /login/ inside container (${mobsf_name})..."
  for ((i=1; i<=tries; i++)); do
    if mobsf_pd exec "${mobsf_name}" sh -lc "${ready_cmd}"; then
      ok "MobSF responding inside container"
      printf '%s\n' "${mobsf_name}"
      return 0
    fi
    if (( i == tries )); then
      mobsf_pd logs --tail=250 "${mobsf_name}" || true
      local djq
      djq="$(mobsf_container_for_service djangoq)"
      [[ -n "${djq}" ]] && mobsf_pd logs --tail=250 "${djq}" || true
      mobsf_init_paths
      ls -ldZ "${MOBSF_DATA_DIR}" "${MOBSF_PG_DIR}" 2>/dev/null || true
      die_with_hint "MobSF failed to become ready" \
        "Inspect container logs above; reset: sudo -E ./mobsf/mobsf_reset.sh --keep"
    fi
    sleep 2
  done
}

mobsf_stack_up_ordered() {
  mobsf_compose_cd || die "Compose dir not found"
  mobsf_compose_validate "${MOBSF_COMPOSE_FILE}"

  info "Starting postgres..."
  require_ok "Postgres container start failed" \
    mobsf_pc_action "Postgres container start" up -d --force-recreate postgres
  mobsf_wait_postgres >/dev/null

  info "Starting mobsf + djangoq..."
  require_ok "MobSF application container start failed" \
    mobsf_pc_action "MobSF application container start" up -d --force-recreate mobsf djangoq
  mobsf_wait_for_container djangoq 60 >/dev/null || warn "djangoq container slow to appear"
  mobsf_wait_mobsf_internal >/dev/null

  info "Starting nginx..."
  require_ok "MobSF nginx container start failed" \
    mobsf_pc_action "MobSF nginx container start" up -d --force-recreate nginx
  mobsf_wait_for_container nginx 60 >/dev/null || die_with_hint \
    "nginx container did not appear" "Run: ./mobsf/mobsf_doctor.sh"
  sleep 2

  if mobsf_check_ui_http; then
    ok "MobSF UI reachable at ${MOBSF_UI_URL}"
  else
    local nginx_name
    nginx_name="$(mobsf_container_for_service nginx)"
    [[ -n "${nginx_name}" ]] && mobsf_pd logs --tail=150 "${nginx_name}" || true
    die_with_hint "MobSF UI not healthy at ${MOBSF_LOGIN_URL}" \
      "Run: ./mobsf/mobsf_doctor.sh  ·  reset: sudo -E ./mobsf/mobsf_reset.sh --keep"
  fi
}

mobsf_stack_reset() {
  local mode="${1:-nuke}"
  mobsf_init_paths
  mobsf_require_tools_root_ops

  info "MobSF reset mode: ${mode}"
  info "User: $(real_user)  Home: $(real_home)"
  info "Compose: ${MOBSF_COMPOSE_DIR_RESOLVED}"
  info "Data: ${MOBSF_DATA_DIR}"
  info "Postgres: ${MOBSF_PG_DIR}"
  echo

  [[ -f "${MOBSF_COMPOSE_FILE}" ]] || die "Compose not found — run: ./mobsf/mobsf_install.sh"
  mobsf_compose_validate "${MOBSF_COMPOSE_FILE}"

  mobsf_stack_down

  local svc name
  for svc in mobsf djangoq nginx postgres; do
    name="$(mobsf_container_for_service "${svc}")"
    [[ -n "${name}" ]] && mobsf_pd rm -f "${name}" 2>/dev/null || true
  done

  mobsf_prepare_data_dirs "${mode}"
  ls -ldZ "${MOBSF_DATA_DIR}" "${MOBSF_PG_DIR}" 2>/dev/null || true
  echo

  mobsf_stack_pull
  echo
  mobsf_stack_up_ordered

  echo
  info "Container status:"
  mobsf_pd ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  ok "MobSF ready at ${MOBSF_UI_URL} (default login: mobsf / mobsf)"
}

mobsf_stack_install() {
  local dest
  mobsf_require_tools_root_ops
  mobsf_init_paths

  info "Installing MobSF Podman stack for $(real_user)..."
  dest="$(mobsf_deploy_compose_bundle "$(mobsf_default_compose_dir)")"
  export MOBSF_COMPOSE_DIR="${dest}"
  mobsf_init_paths

  mobsf_prepare_data_dirs keep
  mobsf_compose_validate "${MOBSF_COMPOSE_FILE}"
  mobsf_stack_pull
  echo
  mobsf_stack_up_ordered

  theme_result_ready "MobSF install complete"
  theme_note "UI: ${MOBSF_UI_URL} · default login: mobsf / mobsf"
  theme_note "Verify: ./mobsf/mobsf_doctor.sh"
}
