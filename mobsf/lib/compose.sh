#!/usr/bin/env bash
# mobsf/lib/compose.sh — MobSF compose bundle deploy and validation
# Do not execute directly.

mobsf_deploy_compose_bundle() {
  local dest="${1:-$(mobsf_default_compose_dir)}"
  local bundle="${MOBSF_BUNDLE_DIR}/compose"
  [[ -f "${bundle}/docker-compose.yml" ]] || die "MobSF bundle missing: ${bundle}/docker-compose.yml"
  [[ -f "${bundle}/nginx.conf" ]] || die "MobSF bundle missing: ${bundle}/nginx.conf"
  run_as_real_user mkdir -p "${dest}"
  cp -f "${bundle}/docker-compose.yml" "${bundle}/nginx.conf" "${dest}/"
  chown "$(real_user):$(real_user)" "${dest}/docker-compose.yml" "${dest}/nginx.conf" 2>/dev/null || true
  run_as_real_user chmod 0644 "${dest}/docker-compose.yml" "${dest}/nginx.conf" 2>/dev/null || true
  ok "Deployed compose bundle to ${dest}"
  printf '%s\n' "${dest}"
}

mobsf_compose_check() {
  local file="${1:-$(mobsf_compose_file)}"
  [[ -f "${file}" ]] || return 1
  grep -qE '^\s*build\s*:' "${file}" && return 1
  grep -qE 'docker\.io/opensecurity/mobile-security-framework-mobsf:latest' "${file}" || return 1
  grep -qE 'postgresql_data:/var/lib/postgresql/data:.*U' "${file}" && return 1
  grep -qE 'postgresql_data:/var/lib/postgresql/data:[^[:space:]]*Z' "${file}" || return 1
  grep -qE 'mobsf_data:/home/mobsf/\.MobSF:[^[:space:]]*Z' "${file}" || return 1
  return 0
}

mobsf_compose_validate() {
  local file="${1:-$(mobsf_compose_file)}"
  [[ -f "${file}" ]] || die "Compose file not found: ${file}"
  if grep -qE '^\s*build\s*:' "${file}"; then
    die "docker-compose.yml contains 'build:' blocks — use mobsf_install.sh to deploy Fedora bundle"
  fi
  if ! grep -qE 'docker\.io/opensecurity/mobile-security-framework-mobsf:latest' "${file}"; then
    die "docker-compose.yml must use docker.io/opensecurity/mobile-security-framework-mobsf:latest"
  fi
  if grep -qE 'postgresql_data:/var/lib/postgresql/data:.*U' "${file}"; then
    die "postgres volume has ':U' — use ':Z' only (run mobsf_install.sh)"
  fi
  if ! grep -qE 'postgresql_data:/var/lib/postgresql/data:[^[:space:]]*Z' "${file}"; then
    die "postgres volume must include ':Z' SELinux label — run mobsf_install.sh to redeploy bundle"
  fi
  if ! grep -qE 'mobsf_data:/home/mobsf/\.MobSF:[^[:space:]]*Z' "${file}"; then
    die "mobsf_data volume must include ':Z' SELinux label — run mobsf_install.sh to redeploy bundle"
  fi
}
