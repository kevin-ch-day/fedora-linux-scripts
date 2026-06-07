#!/usr/bin/env bash
# mobsf/lib/doctor.sh — MobSF readiness diagnostics
# Do not execute directly.

mobsf_doctor() {
  local rc=0 issues=0
  mobsf_init_paths

  common_init_colors
  theme_set_lane mobsf
  theme_report_header "MobSF Doctor" \
    "Fedora / Podman · User: $(real_user) · SELinux: $(getenforce 2>/dev/null || echo unknown)"

  theme_section "Tools"
  if cmd_available podman; then ok "podman: $(podman --version 2>&1 | head -1)"; else err "podman missing"; rc=1; issues=$((issues+1)); fi
  if cmd_available podman-compose; then
    ok "podman-compose: $(podman-compose --version 2>&1 | sed -n '/podman-compose/p' | head -n 1 || podman-compose --version 2>&1 | tail -n 1)"
  else
    err "podman-compose missing (dnf install podman-compose)"; rc=1; issues=$((issues+1))
  fi
  echo

  theme_section "Paths"
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

  theme_section "Compose guardrails"
  if [[ -f "${MOBSF_COMPOSE_FILE}" ]]; then
    if mobsf_compose_check "${MOBSF_COMPOSE_FILE}"; then
      ok "compose file passes Fedora guardrails"
    else
      err "compose validation failed (see details below)"
      mobsf_compose_check_report "${MOBSF_COMPOSE_FILE}" || true
      info "  Redeploy: sudo -E ./mobsf/mobsf_install.sh  or  ./mobsf/mobsf_reset.sh --keep"
      rc=1; issues=$((issues+1))
    fi
    local env_file
    env_file="$(mobsf_compose_env_file "${MOBSF_COMPOSE_DIR_RESOLVED}")"
    if [[ -f "${env_file}" ]]; then
      ok "compose secrets: ${env_file} (mode $(stat -c '%a' "${env_file}" 2>/dev/null || echo ?))"
    else
      warn "compose .env missing — run: sudo -E ./mobsf/mobsf_install.sh or ./mobsf/mobsf_reset.sh --keep"
      issues=$((issues+1))
    fi
  fi
  echo

  theme_section "Containers"
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

  theme_section "HTTP"
  if mobsf_check_ui_http; then
    ok "UI OK: ${MOBSF_LOGIN_URL}"
  else
    err "UI not reachable: ${MOBSF_LOGIN_URL}"
    rc=1; issues=$((issues+1))
  fi
  echo

  echo
  theme_rule '─'
  if (( rc == 0 )); then
    ok "Result: READY"
  else
    warn "Result: ISSUES (${issues} check(s) failed)"
    info "Fresh install: sudo -E ./mobsf/mobsf_install.sh"
    info "Reset stack:    sudo -E ./mobsf/mobsf_reset.sh --keep"
  fi
  theme_rule '─'
  return "${rc}"
}

# Compact check for embedding in combined research doctors (no full banner).
mobsf_doctor_brief() {
  local rc=0 running=0 svc name
  mobsf_init_paths

  if ! cmd_available podman || ! cmd_available podman-compose; then
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

# Dynamic analysis readiness (static stack + ADB/host gateway). Does not configure MobSF.
mobsf_doctor_dynamic() {
  local rc=0 issues=0 fedora_root dev_count=0
  mobsf_init_paths
  fedora_root="$(cd -- "${MOBSF_BUNDLE_DIR}/.." && pwd)"

  common_init_colors
  theme_set_lane mobsf
  theme_report_header "MobSF Dynamic Analysis Readiness" \
    "User: $(real_user) · Host: $(hostname)"
  info "Prerequisite: static MobSF stack running and UI reachable."

  theme_section "Static stack"
  if mobsf_compose_installed && mobsf_check_ui_http; then
    ok "UI reachable: ${MOBSF_LOGIN_URL}"
  else
    warn "Static stack not ready — ./mobsf.sh install && ./mobsf.sh start"
    rc=1
    issues=$((issues + 1))
  fi
  echo

  theme_section "Compose bundle"
  if [[ -f "${MOBSF_COMPOSE_FILE}" ]]; then
    if grep -q 'host\.docker\.internal:host-gateway' "${MOBSF_COMPOSE_FILE}" 2>/dev/null; then
      ok "extra_hosts host.docker.internal present"
    else
      err "host.docker.internal missing — redeploy compose bundle"
      rc=1
      issues=$((issues + 1))
    fi
    if grep -q 'MOBSF_ANALYZER_IDENTIFIER' "${MOBSF_COMPOSE_FILE}" 2>/dev/null; then
      ok "MOBSF_ANALYZER_IDENTIFIER set in compose"
    else
      warn "MOBSF_ANALYZER_IDENTIFIER not set (required for dynamic scans)"
      info "  Docs: https://github.com/MobSF/docs/blob/master/running_mobsf_docker.md"
      issues=$((issues + 1))
    fi
  else
    err "compose file missing — run ./mobsf.sh install"
    rc=1
    issues=$((issues + 1))
  fi
  echo

  theme_section "Host tooling (ADB / Frida)"
  # shellcheck source=../../lib/android.sh
  source "${fedora_root}/lib/android.sh"
  android_user_path_export

  if have adb; then
    ok "adb: $(command -v adb)"
    dev_count="$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device" { c++ } END { print c+0 }')"
    if (( dev_count > 0 )); then
      ok "${dev_count} authorized device(s)"
    else
      warn "No authorized ADB devices — start emulator or connect hardware"
      issues=$((issues + 1))
    fi
  else
    warn "adb not on PATH — sudo ./android/android_dev_core_setup.sh"
    issues=$((issues + 1))
  fi

  if have frida; then
    ok "frida: $(frida --version 2>&1 | head -1)"
  else
    warn "frida not on PATH (common for dynamic instrumentation)"
  fi

  if have objection; then
    ok "objection: $(objection version 2>&1 | head -1)"
  else
    warn "objection not on PATH (optional)"
  fi
  echo

  theme_section "Next steps"
  theme_note "1. Rooted emulator or device visible to host adb"
  theme_note "2. Set MOBSF_ANALYZER_IDENTIFIER in ~/MobSF/compose/docker-compose.yml"
  theme_note "3. Redeploy stack: ./mobsf.sh reset --keep"
  theme_note "4. See mobsf/STACK.md — Dynamic analysis"

  echo
  theme_rule '─'
  if (( rc == 0 && issues == 0 )); then
    ok "Result: READY"
  elif (( rc == 0 )); then
    warn "Result: PARTIAL (${issues} advisory item(s))"
  else
    warn "Result: ISSUES (${issues} item(s) need attention)"
  fi
  theme_rule '─'
  return "${rc}"
}
