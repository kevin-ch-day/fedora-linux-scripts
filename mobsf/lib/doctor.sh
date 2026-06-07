#!/usr/bin/env bash
# mobsf/lib/doctor.sh — MobSF readiness diagnostics
# Do not execute directly.

mobsf_doctor() {
  local rc=0 issues=0
  mobsf_init_paths

  echo "============================================================"
  echo "MobSF Doctor (Fedora / Podman)"
  echo "User: $(real_user)  SELinux: $(getenforce 2>/dev/null || echo unknown)"
  echo "============================================================"
  echo

  echo "== Tools =="
  if have podman; then ok "podman: $(podman --version 2>&1 | head -1)"; else err "podman missing"; rc=1; issues=$((issues+1)); fi
  if have podman-compose; then ok "podman-compose: $(podman-compose --version 2>&1 | head -1)"; else err "podman-compose missing (dnf install podman-compose)"; rc=1; issues=$((issues+1)); fi
  echo

  echo "== Paths =="
  printf '  compose dir : %s\n' "${MOBSF_COMPOSE_DIR_RESOLVED}"
  if [[ -f "${MOBSF_COMPOSE_FILE}" ]]; then
    ok "docker-compose.yml present"
  else
    err "compose missing — run ./mobsf/mobsf_install.sh"
    rc=1; issues=$((issues+1))
  fi
  for d in "${MOBSF_DATA_DIR}" "${MOBSF_PG_DIR}"; do
    if [[ -d "${d}" ]]; then
      ok "data dir: ${d}"
      ls -ldZ "${d}" 2>/dev/null | sed 's/^/    /' || true
      local octal=""
      octal="$(stat -c '%a' "${d}" 2>/dev/null || true)"
      if [[ "${octal}" == "777" ]]; then
        warn "    world-writable (777) — run: sudo -E ./mobsf/mobsf_reset.sh --keep"
      fi
    else
      warn "missing: ${d}"
    fi
  done
  echo

  echo "== Compose guardrails =="
  if [[ -f "${MOBSF_COMPOSE_FILE}" ]]; then
    if mobsf_compose_check "${MOBSF_COMPOSE_FILE}"; then
      ok "compose file passes Fedora guardrails"
    else
      err "compose validation failed (build blocks, image refs, or :U volume)"
      rc=1; issues=$((issues+1))
    fi
  fi
  echo

  echo "== Containers =="
  local svc name running=0
  for svc in postgres mobsf djangoq nginx; do
    name="$(mobsf_container_for_service "${svc}")"
    if [[ -z "${name}" ]]; then
      warn "${svc}: no container found"
      continue
    fi
    if mobsf_pd ps --filter "name=^${name}$" --format "{{.Status}}" 2>/dev/null | grep -qi running; then
      ok "${svc}: ${name} (running)"
      running=$((running+1))
    else
      warn "${svc}: ${name} (not running)"
      issues=$((issues+1))
    fi
  done
  (( running == 4 )) || rc=1
  echo

  echo "== HTTP =="
  if mobsf_check_ui_http; then
    ok "UI OK: ${MOBSF_LOGIN_URL}"
  else
    err "UI not reachable: ${MOBSF_LOGIN_URL}"
    rc=1; issues=$((issues+1))
  fi
  echo

  echo "============================================================"
  if (( rc == 0 )); then
    echo "Result: READY"
  else
    echo "Result: ISSUES (${issues} check(s) failed)"
    echo "[HINT] Fresh install: sudo -E ./mobsf/mobsf_install.sh"
    echo "[HINT] Reset stack:    sudo -E ./mobsf/mobsf_reset.sh --keep"
  fi
  echo "============================================================"
  return "${rc}"
}

# Compact check for embedding in combined research doctors (no full banner).
mobsf_doctor_brief() {
  local rc=0 running=0 svc name
  mobsf_init_paths

  if ! have podman || ! have podman-compose; then
    warn "MobSF: podman/podman-compose not installed"
    return 0
  fi
  if ! mobsf_compose_installed; then
    warn "MobSF: not installed (~/MobSF/compose missing)"
    return 0
  fi
  for svc in postgres mobsf djangoq nginx; do
    name="$(mobsf_container_for_service "${svc}")"
    if [[ -n "${name}" ]] && mobsf_pd ps --filter "name=^${name}$" --format "{{.Status}}" 2>/dev/null | grep -qi running; then
      running=$((running + 1))
    fi
  done
  if (( running == 4 )) && mobsf_check_ui_http; then
    ok "MobSF: READY (${MOBSF_UI_URL})"
  elif (( running > 0 )); then
    warn "MobSF: partial (${running}/4 running) — ./mobsf/mobsf_doctor.sh"
    rc=1
  else
    warn "MobSF: installed but stopped — ./mobsf/mobsf_start.sh"
    rc=1
  fi
  return "${rc}"
}
