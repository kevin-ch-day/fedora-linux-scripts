# MobSF — Troubleshooting on Fedora

Common failures when running MobSF with **Podman**, **SELinux Enforcing**, and this toolkit’s compose bundle.

**Related:** [README](README.md) · [INSTALL](INSTALL.md) · [OPERATIONS](OPERATIONS.md) · [STACK](STACK.md)

---

## Diagnostic first step

Always run:

```bash
./mobsf/mobsf_doctor.sh
```

Doctor checks: podman tools, compose file, data dirs, container state, HTTP on http://127.0.0.1:8080/login/.

For install/reset failures, also inspect:

```bash
./system/log_engine.sh issues --file mobsf.log --lines 80
./system/log_engine.sh tail --file mobsf.log --lines 100
```

---

## Quick fix matrix

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Compose dir not found` | Never installed or path deleted | `sudo -E ./mobsf/mobsf_install.sh` |
| `Compose file contains build:` | Upstream compose copied raw | Re-run install to deploy Fedora bundle |
| UI connection refused on 8080 | Stack stopped | `./mobsf/mobsf_start.sh` or reset `--keep` |
| Permission denied on `.MobSF` | SELinux or ownership | `sudo -E ./mobsf/mobsf_reset.sh --keep` |
| Scans stuck “queued” | djangoq down | `./mobsf/mobsf_logs.sh djangoq --follow` then reset `--keep` |
| Postgres never ready | Corrupt PG data or wrong perms | Backup then nuke reset or fix ownership below |
| Doctor shows containers, HTTP fails | nginx not running or wrong port | `./mobsf/mobsf_logs.sh nginx --tail 50` |
| Old `docker_*_1` names, no compose | Legacy install path removed | [Stale containers](#stale-containers) |

---

## Compose dir not found

**Error:**

```text
Compose dir not found — run mobsf_install.sh
```

**Cause:** `~/MobSF/compose/docker-compose.yml` missing. Common after deleting `~/Downloads/MobSF/` without migrating.

**Fix:**

```bash
sudo -E ./mobsf/mobsf_install.sh
```

Legacy path `~/Downloads/MobSF/docker/` is still detected if present, but new installs should use `~/MobSF/compose/`.

---

## Permission denied on data directories

**Symptoms:**

- MobSF logs show `PermissionError` on `/home/mobsf/.MobSF/`
- Upload fails in UI
- `mobsf_data` or `postgresql_data` owned by numeric UID (e.g. 525286) instead of your user

**Cause:** SELinux Enforcing without `:Z`, or container UIDs writing root-owned host dirs.

**Fix (keep scan data):**

```bash
sudo -E ./mobsf/mobsf_reset.sh --keep
```

This recreates containers, relabels with `chcon`, sets ownership, and applies **0770** on data dirs (owner-only).

If containers fail to write after tightening permissions:

```bash
MOBSF_DATA_DIR_MODE=0777 sudo -E ./mobsf/mobsf_reset.sh --keep
```

**Verify labels:**

```bash
ls -ldZ ~/MobSF/mobsf_data ~/MobSF/postgresql_data
# Expect container_file_t on Enforcing systems
```

**Manual relabel (if reset not an option):**

```bash
sudo chcon -Rt container_file_t ~/MobSF/mobsf_data ~/MobSF/postgresql_data
sudo chown -R "$USER:$USER" ~/MobSF/mobsf_data ~/MobSF/postgresql_data
```

---

## SELinux / `:Z` / `:U` issues

**Error from reset script:**

```text
postgres volume still has ':U'. It must be ':Z' only.
```

**Cause:** Podman `:U` relabeling conflicts with shared/host access patterns on Fedora.

**Fix:** Use the repo bundle (has `:Z` only). Re-deploy:

```bash
sudo -E ./mobsf/mobsf_install.sh
```

Do not copy upstream compose without adding `:Z` to:

- `$HOME/MobSF/mobsf_data:/home/mobsf/.MobSF:Z`
- `$HOME/MobSF/postgresql_data:/var/lib/postgresql/data:Z`
- `./nginx.conf:/etc/nginx/nginx.conf:ro,Z`

---

## Stale containers

**Symptoms:**

- `podman ps -a` shows `docker_postgres_1`, `docker_mobsf_1`, etc. (Exited)
- `~/MobSF/compose/` missing
- Doctor warns containers not running

**Cause:** Old project under `~/Downloads/MobSF/docker` removed; containers orphaned.

**Fix:**

```bash
./mobsf/mobsf_cleanup.sh
sudo -E ./mobsf/mobsf_install.sh
```

Or manually:

```bash
podman rm -f $(podman ps -aq --filter label=io.podman.compose.service) 2>/dev/null || true
```

To keep Postgres data from old stack, back up first:

```bash
tar -czvf ~/MobSF-pg-backup.tar.gz ~/MobSF/postgresql_data ~/MobSF/mobsf_data
```

---

## Postgres did not become ready

**Error during install/reset:**

```text
postgres did not become ready
```

**Steps:**

1. Read postgres logs:
   ```bash
   ./mobsf/mobsf_logs.sh postgres --tail 200
   ```
2. Check data dir permissions (see above).
3. If PG data corrupt, nuke reset:
   ```bash
   sudo -E ./mobsf/mobsf_reset.sh
   ```
   Warning: deletes all scans.

---

## MobSF never became ready (internal :8000)

**Error:**

```text
MobSF failed to become ready
```

**Steps:**

1. MobSF + djangoq logs:
   ```bash
   ./mobsf/mobsf_logs.sh mobsf --tail 250
   ./mobsf/mobsf_logs.sh djangoq --tail 250
   ```
2. Confirm postgres ready (doctor / logs).
3. Retry:
   ```bash
   sudo -E ./mobsf/mobsf_reset.sh --keep
   ```

Common causes: first-start migrations slow (wait longer), DB connection refused, volume permission errors.

---

## HTTP 000 / UI not reachable on 8080

**Symptoms:** Doctor reports UI not reachable; curl returns 000.

**Checks:**

```bash
./mobsf/mobsf_status.sh
ss -tlnp | grep 8080
curl -v http://127.0.0.1:8080/login/
```

1. **nginx not running** → `./mobsf/mobsf_start.sh` or reset `--keep`.
2. **Port in use** → another process bound 8080; change compose port mapping (advanced) or stop conflicting service.
3. **Firewall** (uncommon on localhost):
   ```bash
   sudo firewall-cmd --list-ports
   ```

---

## podman-compose vs sudo

**Rule:** Install and reset use **`sudo -E`**, not plain `sudo`.

`-E` preserves your environment so:

- `$HOME` points at `/home/youruser`, not `/root`
- Compose volume paths `$HOME/MobSF/...` resolve correctly
- Rootless Podman runs as `SUDO_USER`

**Wrong:**

```bash
sudo ./mobsf/mobsf_install.sh    # may break $HOME paths
```

**Right:**

```bash
sudo -E ./mobsf/mobsf_install.sh
```

Day-to-day **stop**, **doctor**, **logs** can run as your user without sudo.

---

## Image pull failures

**Symptoms:** `podman-compose pull` fails with registry timeout or denied.

**Fixes:**

- Retry on network glitch.
- Use full image name (bundle already does):
  `docker.io/opensecurity/mobile-security-framework-mobsf:latest`
- Manual pull test:
  ```bash
  podman pull docker.io/opensecurity/mobile-security-framework-mobsf:latest
  ```

---

## Guardrail errors from reset

| Message | Meaning |
|---------|---------|
| `build: blocks` | Compose tries local Docker build — redeploy Fedora bundle |
| `must use docker.io/opensecurity/...` | Short image name — redeploy bundle |
| `postgres volume ... :U` | Wrong SELinux mount flag — redeploy bundle |

---

## After Fedora system upgrade

1. Reboot if kernel updated.
2. `./mobsf/mobsf_doctor.sh`
3. If issues:
   ```bash
   sudo -E ./mobsf/mobsf_update.sh
   ```
   or reset `--keep`.

SELinux policy updates occasionally require relabel — reset `--keep` handles that.

---

## Getting help / reporting issues

Include in bug reports:

```bash
./mobsf/mobsf_doctor.sh 2>&1 | tee /tmp/mobsf-doctor.txt
./mobsf/mobsf_status.sh 2>&1 | tee -a /tmp/mobsf-doctor.txt
getenforce
podman --version
podman-compose --version
ls -ldZ ~/MobSF/mobsf_data ~/MobSF/postgresql_data 2>&1
```

Session log (sanitize if sharing):

```bash
./system/log_engine.sh tail --file mobsf.log --lines 150
```

---

## See also

- Clean install → [INSTALL.md](INSTALL.md)
- Normal operations → [OPERATIONS.md](OPERATIONS.md)
- Architecture / ports → [STACK.md](STACK.md)
