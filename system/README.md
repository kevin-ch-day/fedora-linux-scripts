# System Lane

Host maintenance, snapshots, logs, and the full research doctor.

**Menu:** `./system/system.sh` · **From picker:** `./fedora.sh` → [1] (returns to picker on [0])

---

## Quick commands

| Task | Command |
|------|---------|
| Full Fedora update | `sudo ./system/system_update.sh` |
| Host snapshot | `./system/system_info.sh` |
| Live monitor | `./system/system_monitor.sh` |
| Backup state (pre-reinstall) | `./system/backup_state.sh` |
| Logs CLI | `./system/log_engine.sh status` |
| Research doctor (Android + MobSF) | `./system/research_doctor.sh` |
| Guided rebuild | `./fedora_rebuild.sh` |

---

## Menu structure

```text
system/system.sh
├── [1] Host visibility     info · monitor · health snapshot · disk · top procs
├── [2] Maintenance         update · backup · cleanup · failed units
├── [3] Logs                log_engine wrappers (tail, follow, issues, …)
└── [4] Research doctor     Android RE + MobSF readiness
```

CLI shortcuts: `./system/system.sh update|info|monitor|backup|doctor|logs`

---

## Logs

Preferred: **`./system/log_engine.sh`**

```bash
./system/log_engine.sh list
./system/log_engine.sh tail --file system_update.log --lines 50
./system/log_engine.sh --file fedora_rebuild.log summary   # options before or after command
./system/log_engine.sh issues --file system_update.log --lines 80
```

Deprecated shim: `./system/view_logs.sh` (maps legacy flags → log_engine)

Log files: `logs/system_update.log`, `logs/fedora_rebuild.log`, `logs/mobsf.log`, `logs/android_dev_core.log`

See [logs/README.md](../logs/README.md).

---

## Doctors

| Script | Scope |
|--------|-------|
| `research_doctor.sh` | Android **+** MobSF (use after rebuild) |
| `android/doctor_android_research.sh` | Android only |
| `mobsf/mobsf_doctor.sh` | MobSF only |

Orchestration: `lib/research.sh` · Do not run Android doctor and research doctor back-to-back after rebuild.

---

## Libraries used

- `lib/health.sh` — metrics, `health_print_system_info()`
- `lib/logging.sh` — log_engine + `logging_view_logs_legacy()`
- `lib/packages.sh` — DNF helpers (update, cleanup)
- `lib/research.sh` — combined research doctor

See [GETTING-STARTED.md](../GETTING-STARTED.md) · [CONSOLIDATION.md](../CONSOLIDATION.md)
