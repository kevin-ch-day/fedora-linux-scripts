# MobSF — Fedora / Podman

**Web UI:** http://127.0.0.1:8080/ · **Login:** `mobsf` / `mobsf` · **Entry:** `./mobsf.sh`

MobSF is **not** a `./run.sh` lane — separate Podman stack lifecycle. Upstream Docker docs assume Ubuntu; this repo ships a Fedora-patched compose bundle ([STACK.md](STACK.md)).

**Also read:** [STACK.md](STACK.md) (architecture) · [TROUBLESHOOTING.md](TROUBLESHOOTING.md) (SELinux / failures)

---

## Quick reference

| Task | Command |
|------|---------|
| Install (first time) | `sudo -E ./mobsf/mobsf_install.sh` or `./mobsf.sh install` |
| Health check | `./mobsf.sh --doctor` |
| Dynamic readiness | `./mobsf.sh --doctor --dynamic` |
| Start / stop | `./mobsf.sh start` · `./mobsf.sh stop` |
| Update / reset | `./mobsf.sh update` · `sudo -E ./mobsf/mobsf_reset.sh --keep` |
| Menu | `./mobsf.sh` |
| Autostart | `./mobsf.sh autostart install` |

Host paths: `~/MobSF/compose/`, `~/MobSF/mobsf_data/`, `~/MobSF/postgresql_data/` · Logs: `logs/mobsf.log`

---

## First-time install

### Prerequisites

Fedora + network · `podman` + `podman-compose` · port **8080** free · *(recommended)* `sudo ./dev/fedora_container_kvm_setup.sh`

### Install

```bash
sudo -E ./mobsf/mobsf_install.sh
./mobsf/mobsf_doctor.sh
xdg-open http://127.0.0.1:8080/
```

Deploys compose + `.env`, SELinux labels, ordered startup, session log. **Use `sudo -E`** so `$HOME` stays your user's.

### Verify & broken setups

| Situation | Command |
|-----------|---------|
| Fresh | `sudo -E ./mobsf/mobsf_install.sh` |
| Orphans | `./mobsf/mobsf_cleanup.sh` then install |
| Broken, keep scans | `sudo -E ./mobsf/mobsf_reset.sh --keep` |
| Clean slate | `sudo -E ./mobsf/mobsf_reset.sh` |

During `./run.sh --rebuild`, optional MobSF step runs install or reset `--keep`.

---

## Day-to-day operations

### Menu

```text
[1] Stack control   [2] Setup   [3] Doctor   [4] Maintenance   [5] Logs   [6] Documentation
```

CLI: `./mobsf.sh install|start|stop|status|logs|update|cleanup|autostart|--doctor [--dynamic]`

**Two log channels:** container stdout (`mobsf_logs.sh`) vs toolkit ops log (`log_engine.sh` → `logs/mobsf.log`).

### Start, stop, autostart

```bash
./mobsf/mobsf_start.sh
./mobsf/mobsf_stop.sh
./mobsf.sh autostart install               # after login
sudo ./mobsf.sh autostart install --linger # at boot
```

### Logs

```bash
./mobsf/mobsf_logs.sh mobsf --tail 100 --follow
./mobsf/mobsf_logs.sh djangoq --tail 100    # queued scans
./system/log_engine.sh issues --file mobsf.log
```

### Updates & reset

```bash
sudo -E ./mobsf/mobsf_update.sh
sudo -E ./mobsf/mobsf_reset.sh --keep   # recreate containers, keep data
```

Back up before nuke: `tar -czvf ~/MobSF-backup-$(date +%Y%m%d).tar.gz ~/MobSF/mobsf_data ~/MobSF/postgresql_data`

### Research workflow

1. Local RE via `./run.sh --android`
2. Upload APK to MobSF for static report
3. *(Optional)* Dynamic — `./mobsf.sh --doctor --dynamic`; see [STACK.md](STACK.md#dynamic-analysis-not-enabled-by-default)

Pre-session: `./android/doctor_android_research.sh` && `./mobsf/mobsf_doctor.sh`

### When to run doctor

UI down after reboot · scans stuck queued · after Fedora/SELinux change · before blaming an APK

---

## Scripts

| Script | Purpose |
|--------|---------|
| `./mobsf.sh` | Root entry — menu + CLI |
| `mobsf_install.sh` | Bootstrap (`sudo -E`) |
| `mobsf_doctor.sh` | Readiness (`--dynamic`) |
| `mobsf_start.sh` / `mobsf_stop.sh` | Stack control |
| `mobsf_update.sh` / `mobsf_reset.sh` | Images + migrate / rebuild |
| `mobsf_autostart.sh` | systemd user unit |
| `mobsf_cleanup.sh` | Orphan containers |

Implementation: `mobsf/lib/` · Compose: `mobsf/compose/`

---

## External links

- [MobSF project](https://github.com/MobSF/Mobile-Security-Framework-MobSF)
- [MobSF Docker docs](https://github.com/MobSF/docs/blob/master/docker_options.md)
- [MobSF API docs](https://mobsf.github.io/docs/)
