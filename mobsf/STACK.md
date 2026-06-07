# MobSF — Stack architecture (Fedora / Podman)

How the four-container MobSF stack works in this toolkit, and how it differs from upstream MobSF docs.

**Related:** [README](README.md) · [INSTALL](INSTALL.md) · [OPERATIONS](OPERATIONS.md) · [TROUBLESHOOTING](TROUBLESHOOTING.md)

---

## Overview

```text
 Browser
    │
    ▼  http://127.0.0.1:8080
┌─────────┐
│  nginx  │  :4000 → proxy → mobsf:8000 (web UI)
│         │  :4001 → proxy → mobsf:1337 (websocket/aux)
└────┬────┘
     │
     ▼
┌─────────┐     ┌──────────┐
│  mobsf  │────▶│ postgres │  scan metadata + Django ORM
│  :8000  │     │  :5432   │
└────┬────┘     └──────────┘
     │
     │ shared volume ~/MobSF/mobsf_data → /home/mobsf/.MobSF
     ▼
┌─────────┐
│ djangoq │  background scan workers (MOBSF_ASYNC_ANALYSIS=1)
└─────────┘
```

All services run on a Podman bridge network (`mobsf_network`). **Rootless Podman** runs as your login user; install/reset scripts use `sudo -E` only for host-side SELinux and directory ownership.

---

## Services

| Service | Image | Role |
|---------|-------|------|
| **postgres** | `docker.io/library/postgres:14` | Database (`mobsf` DB, user `postgres`) |
| **mobsf** | `docker.io/opensecurity/mobile-security-framework-mobsf:latest` | Django web app, static analysis engine |
| **djangoq** | Same MobSF image | Runs `qcluster.sh` — async scan queue |
| **nginx** | `docker.io/library/nginx:latest` | Reverse proxy, large upload body (256M) |

Source of truth in repo: `mobsf/compose/docker-compose.yml`.

---

## Ports (host)

| Host port | Container | Purpose |
|-----------|-----------|---------|
| **8080** | nginx:4000 | **Web UI** — use this in browser |
| **1337** | nginx:4001 | Aux/websocket path (MobSF internal) |
| 8000 | mobsf:8000 | Not exposed on host by default; nginx fronts it |

Upstream MobSF often maps port **80**. We use **8080** so Apache/httpd from `lamp_python_setup.sh` can keep port 80.

Internal health checks hit `http://127.0.0.1:8000/login/` **inside** the mobsf container before nginx starts.

---

## Data directories (host)

| Host path | Mount in container | Contents |
|-----------|-------------------|----------|
| `~/MobSF/mobsf_data` | `/home/mobsf/.MobSF` | Uploads, scan results, MobSF config, API key |
| `~/MobSF/postgresql_data` | `/var/lib/postgresql/data` | Postgres cluster files |
| `~/MobSF/compose/` | (not mounted) | `docker-compose.yml`, `nginx.conf` |

Volume suffix **`:Z`** tells Podman to relabel content for SELinux on Fedora. Install/reset also run `chcon -Rt container_file_t` on host paths when Enforcing.

---

## Startup order

Scripts do **not** rely on a single `podman-compose up -d` because postgres must be ready before MobSF migrations/connections succeed.

```text
1. postgres        → wait pg_isready
2. mobsf + djangoq → wait /login/ inside mobsf container
3. nginx           → wait http://127.0.0.1:8080/login/ on host
```

Implemented in **`mobsf/lib/stack.sh`** → `mobsf_stack_up_ordered()`.

---

## Fedora patches vs upstream

Upstream [MobSF compose](https://github.com/MobSF/Mobile-Security-Framework-MobSF/blob/master/docker/docker-compose.yml) includes:

| Upstream | Fedora bundle |
|----------|---------------|
| `build:` from Dockerfile | **Removed** — prebuilt images only |
| `$HOME/MobSF/...` without `:Z` | **`:Z` on all bind mounts** |
| `opensecurity/...` short names | **`docker.io/opensecurity/...`** full refs |
| Ports `80:4000` | **`8080:4000`** |
| postgres volume sometimes `:U` | **`:Z` only** (reset rejects `:U`) |

Do not replace `~/MobSF/compose/docker-compose.yml` with upstream raw copy without applying these changes.

---

## Container names

Podman Compose names containers like `{project}_{service}_1`. Project name comes from the compose directory (e.g. `compose_postgres_1`).

Scripts discover containers by **label** (`io.podman.compose.service=postgres`), not hardcoded names — so legacy `docker_postgres_1` from old `~/Downloads/MobSF/docker` projects still show up in doctor until removed.

---

## Environment highlights

| Variable | Set on | Meaning |
|----------|--------|---------|
| `MOBSF_ASYNC_ANALYSIS=1` | mobsf | Scans run via djangoq queue |
| `POSTGRES_*` | mobsf, djangoq | DB connection (password `password` in default bundle — change for untrusted networks) |
| `host.docker.internal:host-gateway` | mobsf | Host reachability for future dynamic analysis / ADB |

---

## Dynamic analysis (not enabled by default)

Static analysis works out of the box. Dynamic analysis requires:

- Rooted Android emulator or device reachable from container
- `MOBSF_ANALYZER_IDENTIFIER` env (see [MobSF Docker docs](https://github.com/MobSF/docs/blob/master/running_mobsf_docker.md))
- Often `--add-host=host.docker.internal:host-gateway` (already in bundle)

This toolkit does not yet automate dynamic setup; track as future `mobsf_dynamic_setup.sh` if needed.

---

## Implementation map

| Concern | Location |
|---------|----------|
| Compose bundle | `mobsf/compose/` |
| Stack logic | `mobsf/lib/` (`stack.sh`, `podman.sh`, …) |
| CLI scripts | `mobsf/mobsf_*.sh` |
| Menu | `fedora.sh` → MobSF |
| Session logs | `logs/mobsf.log` |

---

## See also

- Install walkthrough → [INSTALL.md](INSTALL.md)
- Commands cheat sheet → [OPERATIONS.md](OPERATIONS.md)
- SELinux / permission fixes → [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
