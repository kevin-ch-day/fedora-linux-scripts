# MobSF — Troubleshooting on Fedora

Podman + SELinux failures for this toolkit’s compose bundle. **First step:** `./mobsf/mobsf_doctor.sh`

**Related:** [GUIDE](GUIDE.md) · [STACK](STACK.md)

---

## Quick fix matrix

| Symptom | Fix |
|---------|-----|
| Compose dir missing | `sudo -E ./mobsf/mobsf_install.sh` |
| Upstream compose / `build:` / `:U` / wrong image refs | Re-deploy Fedora bundle: `sudo -E ./mobsf/mobsf_install.sh` |
| UI refused on :8080 | `./mobsf/mobsf_start.sh` or `sudo -E ./mobsf/mobsf_reset.sh --keep` |
| Permission denied on `.MobSF` / wrong ownership | `sudo -E ./mobsf/mobsf_reset.sh --keep` (relabel + 0770) |
| Still permission errors after reset | `MOBSF_DATA_DIR_MODE=0777 sudo -E ./mobsf/mobsf_reset.sh --keep` |
| Scans stuck “queued” | `./mobsf/mobsf_logs.sh djangoq --follow` → reset `--keep` |
| Postgres not ready / corrupt DB | Logs: `./mobsf/mobsf_logs.sh postgres --tail 200` → reset or nuke |
| MobSF internal :8000 not ready | `./mobsf/mobsf_logs.sh mobsf --tail 250` → reset `--keep` |
| HTTP 000 / nginx down | `./mobsf/mobsf_status.sh` · `./mobsf/mobsf_logs.sh nginx --tail 50` |
| Stale `docker_*_1` containers | `./mobsf/mobsf_cleanup.sh` → install |
| Install/reset failed | `./system/log_engine.sh issues --file mobsf.log --lines 80` |

---

## Permission & SELinux

**Symptoms:** `PermissionError` on `/home/mobsf/.MobSF/`, upload fails, dirs owned by container UID.

```bash
sudo -E ./mobsf/mobsf_reset.sh --keep
ls -ldZ ~/MobSF/mobsf_data ~/MobSF/postgresql_data   # expect container_file_t
```

Manual relabel if reset is not an option:

```bash
sudo chcon -Rt container_file_t ~/MobSF/mobsf_data ~/MobSF/postgresql_data
sudo chown -R "$USER:$USER" ~/MobSF/mobsf_data ~/MobSF/postgresql_data
```

Bundle must use **`:Z` only** on volumes (not `:U`). Do not paste upstream compose without Fedora patches — see [STACK.md](STACK.md#fedora-patches-vs-upstream).

---

## Stale containers

Old `~/Downloads/MobSF/docker` projects leave `docker_postgres_1`-style orphans:

```bash
./mobsf/mobsf_cleanup.sh
sudo -E ./mobsf/mobsf_install.sh
```

Back up before nuke: `tar -czvf ~/MobSF-backup.tar.gz ~/MobSF/mobsf_data ~/MobSF/postgresql_data`

---

## sudo -E (install / reset)

Install and reset **must** use `sudo -E`, not plain `sudo`, so `$HOME` stays `/home/youruser` and compose paths resolve. Stop, doctor, and logs run as your user without sudo.

---

## HTTP / port 8080

```bash
./mobsf/mobsf_status.sh
ss -tlnp | grep 8080
curl -v http://127.0.0.1:8080/login/
```

If another service owns 8080, stop it or adjust compose (advanced).

---

## Image pull failures

Retry network; bundle uses full refs e.g. `docker.io/opensecurity/mobile-security-framework-mobsf:latest`. Test: `podman pull docker.io/opensecurity/mobile-security-framework-mobsf:latest`

---

## After Fedora upgrade

Reboot if needed → `./mobsf/mobsf_doctor.sh` → `sudo -E ./mobsf/mobsf_update.sh` or reset `--keep`.

---

## Bug report bundle

```bash
./mobsf/mobsf_doctor.sh 2>&1 | tee /tmp/mobsf-doctor.txt
./mobsf/mobsf_status.sh 2>&1 | tee -a /tmp/mobsf-doctor.txt
getenforce; podman --version; podman-compose --version
ls -ldZ ~/MobSF/mobsf_data ~/MobSF/postgresql_data 2>&1
./system/log_engine.sh tail --file mobsf.log --lines 150
```

---

## See also

- [GUIDE.md](GUIDE.md) — install & operations
- [STACK.md](STACK.md) — ports, data dirs, lib modules
