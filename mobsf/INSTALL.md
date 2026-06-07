# MobSF — First-time install on Fedora

Step-by-step guide for bringing up MobSF on a Fedora workstation using **rootless Podman**. This matches what `mobsf_install.sh` automates.

**Related:** [README](README.md) · [OPERATIONS](OPERATIONS.md) · [STACK](STACK.md) · [TROUBLESHOOTING](TROUBLESHOOTING.md)

---

## Before you start

### What you get

| Item | Value |
|------|-------|
| Web UI | http://127.0.0.1:8080/ |
| Default login | `mobsf` / `mobsf` |
| Compose location | `~/MobSF/compose/` |
| Data | `~/MobSF/mobsf_data`, `~/MobSF/postgresql_data` |

### Prerequisites

1. **Fedora** with network access (image pulls are several GB).
2. **Podman** and **podman-compose** — installed by the script if missing, or via:
   ```bash
   sudo dnf install -y podman podman-compose
   ```
3. **Containers/KVM setup** (optional but recommended first):
   ```bash
   sudo ./dev/fedora_container_kvm_setup.sh
   ```
4. **Port 8080 free** — the stack binds UI to 8080 (not 80) to avoid clashing with Apache/httpd from the LAMP scripts.

### Why not follow upstream MobSF docs verbatim?

Upstream [MobSF Docker Compose docs](https://github.com/MobSF/docs/blob/master/docker_options.md) assume Docker on Ubuntu. On Fedora with **SELinux Enforcing** and **Podman**, you typically hit:

- `build:` blocks in compose (Podman expects prebuilt images)
- Missing `:Z` on volume mounts → permission denied
- Wrong image names without `docker.io/` prefix

This repo ships a **Fedora-patched bundle** in `mobsf/compose/` and deploys it to `~/MobSF/compose/`.

---

## Install (automated — recommended)

From the repo root:

```bash
sudo -E ./mobsf/mobsf_install.sh
```

Or interactive menu:

```bash
./fedora.sh
# → [4] MobSF → [1] Install / bootstrap
```

### What the install script does

1. Installs `podman`, `podman-compose`, `curl` if missing (dnf).
2. Copies `mobsf/compose/docker-compose.yml` and `nginx.conf` → `~/MobSF/compose/`.
3. Creates data directories and applies SELinux labels (`container_file_t`).
4. Runs `podman-compose pull` (downloads postgres, nginx, MobSF images).
5. Starts services in order: **postgres → mobsf + djangoq → nginx**.
6. Waits until http://127.0.0.1:8080/login/ returns HTTP 2xx.
7. Logs the session to `logs/mobsf.log`.

**Use `sudo -E`** so `$HOME` and Podman’s rootless context stay tied to your user (`SUDO_USER`), not root.

---

## Verify install

```bash
./mobsf/mobsf_doctor.sh
```

Expected ending:

```text
Result: READY
```

Open the UI:

```bash
xdg-open http://127.0.0.1:8080/
```

Log in with `mobsf` / `mobsf`, then **change the password** under account settings if the instance is reachable from your network.

---

## First scan (smoke test)

1. Open http://127.0.0.1:8080/
2. Upload a small APK (or drag-and-drop).
3. Wait for static analysis to complete (async queue uses **djangoq**).
4. Review findings in the report view.

If upload fails with permission errors, see [TROUBLESHOOTING](TROUBLESHOOTING.md#permission-denied-on-data-directories).

---

## Install after a partial / broken setup

| Situation | Command |
|-----------|---------|
| Never installed | `sudo -E ./mobsf/mobsf_install.sh` |
| Compose missing, old containers exist | Remove orphans (see [TROUBLESHOOTING](TROUBLESHOOTING.md#stale-containers)), then install |
| Compose OK, containers broken, **keep scans** | `sudo -E ./mobsf/mobsf_reset.sh --keep` |
| Corrupt DB or clean slate | `sudo -E ./mobsf/mobsf_reset.sh` (nuke data) |

---

## Install as part of full workstation rebuild

```bash
./fedora_rebuild.sh
```

At the optional MobSF step:

- If `~/MobSF/compose/docker-compose.yml` **missing** → runs **install**
- If compose **exists** → runs **reset --keep**

With `--yes`, MobSF is skipped; run install manually from the MobSF menu afterward.

---

## Manual install (understand what automation does)

Only use this if you need to debug; prefer `mobsf_install.sh`.

```bash
# 1. Tools
sudo dnf install -y podman podman-compose curl

# 2. Deploy bundle
mkdir -p ~/MobSF/compose
cp /path/to/fedora-linux-scripts/mobsf/compose/* ~/MobSF/compose/

# 3. Data dirs + SELinux (needs root on Enforcing systems)
sudo mkdir -p ~/MobSF/mobsf_data ~/MobSF/postgresql_data
sudo chcon -Rt container_file_t ~/MobSF/mobsf_data ~/MobSF/postgresql_data
sudo chown -R "$USER:$USER" ~/MobSF/mobsf_data ~/MobSF/postgresql_data

# 4. Pull and start
cd ~/MobSF/compose
podman-compose pull
podman-compose up -d postgres
# wait for postgres, then:
podman-compose up -d mobsf djangoq nginx
```

Ordered startup and health checks live in **`mobsf/lib/stack.sh`** — use `./mobsf/mobsf_start.sh` instead of raw `up` when possible.

---

## Next steps

- Day-to-day commands → [OPERATIONS.md](OPERATIONS.md)
- How the four containers fit together → [STACK.md](STACK.md)
- When something fails → [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
