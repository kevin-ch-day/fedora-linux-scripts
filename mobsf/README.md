# MobSF on Fedora (Podman)

Mobile Security Framework static analysis for the **neptune** Android security research workstation.

**Web UI:** http://127.0.0.1:8080/ · **Login:** `mobsf` / `mobsf`

---

## Documentation

| Guide | When to read |
|-------|----------------|
| **[INSTALL.md](INSTALL.md)** | First-time setup, prerequisites, verify, smoke test |
| **[OPERATIONS.md](OPERATIONS.md)** | Start/stop, logs, updates, resets, scan workflow |
| **[STACK.md](STACK.md)** | Containers, ports, data dirs, Fedora vs upstream compose |
| **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** | SELinux, permissions, stale containers, HTTP failures |
| **[lib/README.md](lib/README.md)** | Shared library modules (`mobsf/lib/`) |

---

## Quick start

```bash
# From repo root
sudo -E ./mobsf/mobsf_install.sh
./mobsf/mobsf_doctor.sh
xdg-open http://127.0.0.1:8080/
```

Or run the **MobSF lane menu** directly:

```bash
./mobsf/mobsf.sh
```

Or **`./fedora.sh` → [4] MobSF** (returns to picker on [0]).

---

## Scripts

| Script | Sudo | Purpose |
|--------|------|---------|
| **`mobsf.sh`** | No | **Lane launcher** — grouped menu + CLI shortcuts |
| `mobsf_install.sh` | `sudo -E` | First-time bootstrap |
| `mobsf_doctor.sh` | No | Readiness check |
| `mobsf_start.sh` | Optional | Start stack |
| `mobsf_stop.sh` | No | Stop stack |
| `mobsf_logs.sh` | No | Service logs |
| `mobsf_update.sh` | `sudo -E` | Pull images + migrate |
| `mobsf_reset.sh` | `sudo -E` | Rebuild (`--keep` to preserve data) |
| `mobsf_status.sh` | No | Container table |
| `mobsf_cleanup.sh` | No | Remove orphan compose containers |

Implementation: **`mobsf/lib/`** · Compose bundle: **`mobsf/compose/`**

```text
mobsf/
├── mobsf.sh           ← lane launcher (standalone menu)
├── lib/           ← shared MobSF library (paths, podman, stack, doctor, menu)
├── compose/       ← Fedora-patched docker-compose + nginx
├── *.sh           ← CLI scripts
└── *.md           ← documentation
```

---

## Layout

```text
~/MobSF/
├── compose/           ← docker-compose.yml + nginx.conf (deployed by install)
├── mobsf_data/        ← scans, uploads, config
└── postgresql_data/   ← database files

logs/mobsf.log   ← install / reset / update sessions
```

---

## Why this exists

Upstream MobSF Docker docs target Docker on Ubuntu. Fedora adds **SELinux**, **rootless Podman**, and **port 80 conflicts** with httpd. This repo ships a patched compose bundle and scripts so install is repeatable — see [STACK.md](STACK.md).

---

## External links

- [MobSF project](https://github.com/MobSF/Mobile-Security-Framework-MobSF)
- [MobSF Docker docs](https://github.com/MobSF/docs/blob/master/docker_options.md)
- [MobSF API docs](https://mobsf.github.io/docs/)
