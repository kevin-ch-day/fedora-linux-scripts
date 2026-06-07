# Fedora toolkit logging engine

Operational logs for the Fedora rebuild kit. Implementation: **`lib/logging.sh`** (engine) + **`system/log_engine.sh`** (CLI).

## Layout

```text
logs/
├── README.md              # this file
├── system_update.log      # system/system_update.sh (always)
├── fedora_rebuild.log     # fedora_rebuild.sh --log
├── mobsf.log              # mobsf install/reset/update (was mobsf_reset.log)
├── android_dev_core.log   # android/android_dev_core_setup.sh (always)
├── archive/               # rotated/archived copies (*.log)
└── backups/               # backup_state exports (not runtime logs)
```

## Engine architecture

```text
lib/logging.sh          ← core engine (write + read + maintenance)
system/log_engine.sh    ← CLI to inspect/manage logs
system/view_logs.sh     ← deprecated shim (legacy flags → lib/logging.sh)
```

### Write path (scripts)

1. **`init_script_logging FILE SCRIPT TITLE`** — starts a session:
   - optional rotate if `FEDORA_LOG_ROTATE_MB` > 0
   - assigns **Session-ID** (`YYYYMMDD-HHMMSS-PID`)
   - tees stdout/stderr to the log file
   - prints session banner
   - installs EXIT trap → footer + ownership fix

2. **Structured lines** (when session active, captured by tee):

```text
[2026-06-07T12:00:01-05:00] [INFO] [20260607-120001-12345] [system_update.sh] [1/10] Refreshing metadata...
[2026-06-07T12:05:00-05:00] [ERROR] [20260607-120001-12345] [system_update.sh] Session failed with exit code 1
```

3. **API**

| Function | Purpose |
|----------|---------|
| `log_info` / `log_warn` / `log_error` / `log_debug` | Structured level lines |
| `log_step N TOTAL MSG` | Numbered progress `[N/TOTAL]` |
| `log_cmd ...` | Run command; log OK/FAIL with exit code |
| `log_engine_open` / `log_engine_close` | Manual session (no EXIT trap) |

### Environment

| Variable | Default | Meaning |
|----------|---------|---------|
| `FEDORA_LOG_LEVEL` | `INFO` | Minimum level: DEBUG, INFO, WARN, ERROR |
| `FEDORA_LOG_ROTATE_MB` | `0` (global) / `10` for `system_update.sh` | Archive+truncate if log exceeds N MB before new session (0=off) |

Example:

```bash
sudo FEDORA_LOG_LEVEL=DEBUG FEDORA_LOG_ROTATE_MB=10 ./system/system_update.sh
```

### Read / maintenance path (CLI)

```bash
./system/log_engine.sh list
./system/log_engine.sh summary --file system_update.log
./system/log_engine.sh tail --file system_update.log --lines 100
./system/log_engine.sh follow --file system_update.log
./system/log_engine.sh sessions --file system_update.log
./system/log_engine.sh issues --file system_update.log --lines 80
./system/log_engine.sh archive --file system_update.log
./system/log_engine.sh rotate --file system_update.log --max-mb 10
./system/log_engine.sh truncate --file system_update.log
./system/log_engine.sh status
```

Or: **`./system/system.sh` → Logs** (or `./fedora.sh` → System → Logs)

### Session format (human banner + structured lines)

```text
============================================================
Fedora System Update
SESSION START : 2026-06-07T12:00:00-05:00
Session-ID    : 20260607-120000-12345
Script        : system_update.sh
Host          : neptune
Invoker       : secadmin
Log level     : INFO
Log file      : .../fedora-linux-scripts/logs/system_update.log
============================================================

[2026-06-07T12:00:01-05:00] [INFO] [20260607-120000-12345] [system_update.sh] Session started
[2026-06-07T12:00:02-05:00] [INFO] [20260607-120000-12345] [system_update.sh] [1/10] Refreshing metadata...
...
============================================================
Status        : SUCCESS
SESSION END   : 2026-06-07T12:05:00-05:00
Session-ID    : 20260607-120000-12345
Log file      : .../fedora-linux-scripts/logs/system_update.log
============================================================
```

## Policy

| Rule | Detail |
|------|--------|
| **Location** | Always `logs/` at repo root |
| **Naming** | Stable filenames — append-only operational logs |
| **Sessions** | Each run = banner + Session-ID + structured lines + footer |
| **Ownership** | sudo runs → files owned by `SUDO_USER` |
| **Archive** | `log_engine.sh archive` or auto `FEDORA_LOG_ROTATE_MB` → `logs/archive/` |
| **Backups** | `backup_state.sh` → `logs/backups/` (not `.log` files) |

## Scripts that use the engine today

| Script | Log file | When |
|--------|----------|------|
| `system/system_update.sh` | `system_update.log` | Always |
| `fedora_rebuild.sh` | `fedora_rebuild.log` | `--log` |
| `mobsf/mobsf_install.sh` | `mobsf.log` | Always (install/reset/update) |
| `android/android_dev_core_setup.sh` | `android_dev_core.log` | Always |

Other scripts print to terminal only unless you add `init_script_logging` or `--log`.

## Git

`.gitignore` at the repo root excludes `logs/*.log`, `logs/archive/`, `logs/backups/`. Keep this README tracked.
