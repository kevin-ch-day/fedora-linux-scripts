#!/usr/bin/env bash
# mobsf/lib/systemd.sh — MobSF user systemd unit (login autostart)
# Version: 0.1.0
# Do not execute directly.

mobsf_systemd_unit_path() {
  printf '%s/.config/systemd/user/mobsf-stack.service\n' "$(real_home)"
}

mobsf_systemd_compose_workdir() {
  mobsf_init_paths
  printf '%s\n' "${MOBSF_COMPOSE_DIR_RESOLVED}"
}

mobsf_systemd_write_unit() {
  local unit_path pc compose_dir home
  unit_path="$(mobsf_systemd_unit_path)"
  compose_dir="$(mobsf_systemd_compose_workdir)"
  home="$(real_home)"
  pc="$(cmd_binary_path podman-compose 2>/dev/null || true)"

  [[ -n "${pc}" ]] || die "podman-compose not found — install podman-compose first"
  [[ -f "${compose_dir}/docker-compose.yml" ]] || die "Compose not found — run ./mobsf.sh install first"

  run_as_real_user mkdir -p "${home}/.config/systemd/user"

  run_as_real_user tee "${unit_path}" > /dev/null <<EOF
[Unit]
Description=MobSF Podman stack (fedora-linux-scripts)
Documentation=https://github.com/kevin-ch-day/fedora-linux-scripts/tree/main/mobsf
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${compose_dir}
Environment=HOME=${home}
EnvironmentFile=-${compose_dir}/.env
ExecStart=${pc} up -d
ExecStop=${pc} down
TimeoutStartSec=600

[Install]
WantedBy=default.target
EOF

  run_as_real_user chmod 0644 "${unit_path}"
  ok "Wrote user unit: ${unit_path}"
}

mobsf_systemd_install() {
  local enable_linger="${1:-0}"
  mobsf_systemd_write_unit
  run_as_real_user systemctl --user daemon-reload
  require_ok "Failed to enable MobSF user service" \
    run_as_real_user systemctl --user enable mobsf-stack.service
  ok "Enabled: systemctl --user start mobsf-stack.service"

  if (( enable_linger )); then
    require_root "Enable boot-time autostart with: sudo ./mobsf/mobsf_autostart.sh install --linger"
    require_ok "loginctl enable-linger failed" loginctl enable-linger "${SUDO_USER:-$(real_user)}"
    ok "Linger enabled for ${SUDO_USER:-$(real_user)} (stack can start at boot)"
  else
    warn "Starts after login only — for boot autostart: sudo ./mobsf/mobsf_autostart.sh install --linger"
  fi
}

mobsf_systemd_remove() {
  local unit_path
  unit_path="$(mobsf_systemd_unit_path)"
  if [[ -f "${unit_path}" ]]; then
    run_as_real_user systemctl --user disable --now mobsf-stack.service 2>/dev/null || true
    run_as_real_user rm -f "${unit_path}"
    run_as_real_user systemctl --user daemon-reload
    ok "Removed MobSF user systemd unit"
  else
    info "No MobSF user unit installed"
  fi
}

mobsf_systemd_status() {
  local unit_path
  unit_path="$(mobsf_systemd_unit_path)"
  echo "Unit file: ${unit_path}"
  if [[ -f "${unit_path}" ]]; then
    ok "Unit file present"
  else
    warn "Unit file missing — run: ./mobsf/mobsf_autostart.sh install"
  fi
  if run_as_real_user systemctl --user is-enabled mobsf-stack.service >/dev/null 2>&1; then
    ok "Service enabled (user)"
    run_as_real_user systemctl --user status mobsf-stack.service --no-pager 2>/dev/null | sed 's/^/  /' || true
  else
    warn "Service not enabled (user)"
  fi
  if have loginctl; then
    local linger
    linger="$(loginctl show-user "$(real_user)" -p Linger 2>/dev/null | cut -d= -f2 || echo unknown)"
    echo "Linger: ${linger} (yes = can start at boot without login)"
  fi
}
