# MobSF — Day-to-day operations

Commands and workflows for running MobSF on the neptune Fedora workstation after initial install.

**Related:** [README](README.md) · [INSTALL](INSTALL.md) · [STACK](STACK.md) · [TROUBLESHOOTING](TROUBLESHOOTING.md)

---

## Quick reference

| Task | Command |
|------|---------|
| Open UI | http://127.0.0.1:8080/ |
| Health check | `./mobsf/mobsf_doctor.sh` |
| Start stack | `sudo -E ./mobsf/mobsf_start.sh` or `./mobsf/mobsf_start.sh`* |
| Stop stack | `./mobsf/mobsf_stop.sh` |
| Container status | `./mobsf/mobsf_status.sh` |
| Logs (MobSF app) | `./mobsf/mobsf_logs.sh mobsf --tail 100 --follow` |
| Update images | `sudo -E ./mobsf/mobsf_update.sh` |
| Reset, keep data | `sudo -E ./mobsf/mobsf_reset.sh --keep` |
| Reset, wipe all | `sudo -E ./mobsf/mobsf_reset.sh` |
| Interactive menu | `./fedora.sh` → MobSF |

\*Use `sudo -E` for start/reset if SELinux relabeling or ownership fixes are needed on data dirs.

---

## Interactive menu (`fedora.sh`)

```text
MobSF (Podman stack)  →  http://127.0.0.1:8080/

[1] Install / bootstrap (first time, sudo -E)
[2] Doctor — readiness check
[3] Start stack
[4] Stop stack
[5] Logs (mobsf service)
[6] Update images + migrate (sudo -E)
[7] Reset stack — nuke data (sudo -E)
[8] Reset stack — keep data (sudo -E)
[9] Show container status
```

---

## Start and stop

### Start (after reboot or manual stop)

```bash
./mobsf/mobsf_start.sh
```

Starts in dependency order (see [STACK.md](STACK.md)) and checks http://127.0.0.1:8080/login/.

If containers exist but are unhealthy:

```bash
sudo -E ./mobsf/mobsf_reset.sh --keep
```

### Stop (free RAM, no data loss)

```bash
./mobsf/mobsf_stop.sh
```

Equivalent to `podman-compose down` in `~/MobSF/compose/`.

---

## Logs

### Via toolkit script

```bash
# MobSF web app
./mobsf/mobsf_logs.sh mobsf --tail 100

# Async scan workers
./mobsf/mobsf_logs.sh djangoq --tail 100 --follow

# Database
./mobsf/mobsf_logs.sh postgres --tail 50

# Reverse proxy
./mobsf/mobsf_logs.sh nginx --tail 50
```

### Via logging engine (install/reset/update sessions)

```bash
./system/log_engine.sh tail --file mobsf.log --lines 100
./system/log_engine.sh issues --file mobsf.log
./system/log_engine.sh follow --file mobsf.log
```

Or: `./system/system.sh` → Logs → tail `mobsf.log` (or `./fedora.sh` → System → Logs).

### Raw podman (same user as install)

```bash
cd ~/MobSF/compose
podman-compose logs -f mobsf
podman ps -a --filter label=io.podman.compose.service
```

---

## Updates

When upstream MobSF releases a new Docker image:

```bash
sudo -E ./mobsf/mobsf_update.sh
```

This script:

1. `podman-compose pull`
2. Runs `migrate.sh` inside the MobSF container (DB schema updates)
3. Restarts the stack in order

If migrate fails, try reset with kept data:

```bash
sudo -E ./mobsf/mobsf_reset.sh --keep
```

---

## Reset scenarios

| Goal | Command | Data impact |
|------|---------|-------------|
| Recreate containers only | `mobsf_reset.sh --keep` | Keeps Postgres + scan history |
| Fix permissions/SELinux | `mobsf_reset.sh --keep` | Keeps data, relabels dirs |
| Fresh MobSF, no scans | `mobsf_reset.sh` (default) | Deletes `mobsf_data` + `postgresql_data` |
| Re-deploy compose from repo | `mobsf_install.sh` | Overwrites `~/MobSF/compose/` files only |

**Nuke** removes all uploaded APKs and analysis results. Back up `~/MobSF/` first if needed:

```bash
tar -czvf ~/MobSF-backup-$(date +%Y%m%d).tar.gz ~/MobSF/mobsf_data ~/MobSF/postgresql_data
```

---

## Static analysis workflow (research)

Typical flow for Android RE on this workstation:

1. **Extract/decompile locally** — apktool, jadx, smali (Android menu in `fedora.sh`).
2. **Upload to MobSF** — http://127.0.0.1:8080/ for consolidated static report.
3. **Cross-check** — compare MobSF findings with manual RE notes (ObsidianDroid, etc.).
4. **Optional dynamic** — requires extra MobSF + ADB/emulator setup ([MobSF dynamic docs](https://github.com/MobSF/docs/blob/master/running_mobsf_docker.md)); compose includes `host.docker.internal` for future use.

Verify Android tools before a long MobSF session:

```bash
./android/doctor_android_research.sh
./mobsf/mobsf_doctor.sh
```

---

## API access (optional)

MobSF exposes a REST API. The API key is stored in MobSF data after first run (inside the container volume at `/home/mobsf/.MobSF/`).

```bash
# Example: find API key on host (path may vary)
grep -r "APIKEY" ~/MobSF/mobsf_data/ 2>/dev/null | head -5
```

Official API docs: [MobSF documentation](https://mobsf.github.io/docs/).

---

## When to run doctor

Run `./mobsf/mobsf_doctor.sh` when:

- UI does not load after reboot
- Scans hang in “queued” state (check djangoq logs)
- After Fedora upgrade or SELinux policy change
- Before blaming an APK — confirm stack is READY

---

## See also

- First install → [INSTALL.md](INSTALL.md)
- Container topology and ports → [STACK.md](STACK.md)
- Error messages and fixes → [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
