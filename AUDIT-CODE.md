# Fedora Toolkit — Deep Code Audit

**Companion to:** [AUDIT.md](AUDIT.md) (inventory and ops snapshot)  
**Audit date:** 2026-06-07  
**Scope:** All shell code, compose assets, launcher wiring, lib APIs

---

## Methodology

- Read all 41 task scripts, 14 lib modules, compose/nginx assets, launchers
- Cross-checked menu wiring in `fedora.sh` vs script paths
- Traced lib dependency graph for circular imports
- Validated critical paths with `bash -n`
- **ShellCheck 0.11.0** at `-S warning` (2026-06-07) — see [ShellCheck baseline](#shellcheck-baseline)
- Subagent-assisted lane reviews (system/dev, android/legacy, lib/mobsf/launchers)

---

## ShellCheck baseline

Run from repo root (excludes disabled legacy scripts):

```bash
find . -name '*.sh' -type f ! -path './legacy/*' -print0 \
  | xargs -0 shellcheck -S warning
```

| Run | Warnings | Notes |
|-----|----------|-------|
| First pass | 20 | Before fixes |
| After fixes | **0** | Clean at `-S warning` |

Fixes: SC2046/SC2209/SC2164/SC2088/SC2010/SC2155 in task scripts and libs; SC2034 documented for public API globals (`FEDORA_LOG_*`, color vars, `MOBSF_HOME`).

---

## Executive findings

| Severity | Count | Themes |
|----------|------:|--------|
| Critical | 5 | Legacy scripts executable; SDK ownership; orphan cleanup scope; broken `die` |
| High | 8 | Security defaults (phpMyAdmin, phpinfo); backup under sudo; dex2jar verify; compose LAN ports |
| Medium | 12 | MobSF permissions; log_engine option order; BASH_ENV verify edge case |
| Low | 12 | Version drift; dead nginx upstream; dry-run+log edge case |

**Fixes applied this session (2026-06-07):**

| Fix | File(s) |
|-----|---------|
| Source `common.sh` for `die` | `system/research_doctor.sh` |
| `--tail` numeric guard | `system/view_logs.sh` |
| `real_home()` for user paths/git | `system/backup_state.sh` |
| MobSF-scoped orphan cleanup | `mobsf/lib/podman.sh` |
| SDK download/extract as invoker user | `android/android_dev_core_setup.sh` v0.6.1 |
| npm global as invoker user | `android/android_dev_core_setup.sh` |
| dex2jar verify requires all 3 tools | `lib/android.sh` |
| Localhost-only compose ports | `mobsf/compose/docker-compose.yml` |
| Legacy scripts hard-disabled | `legacy/*.sh` |
| `./fedora.sh 1`–`4` lane shortcut | `fedora.sh` v0.5.2 |
| `--all-logs` implies truncate | `system/cleanup.sh` v0.3.1 |
| MobSF data dirs `0770` + group | `mobsf/lib/paths.sh` |
| phpMyAdmin re-run restores localhost | `dev/phpmyadmin_setup.sh` v0.3.1 |
| Compose `:Z` validation | `mobsf/lib/compose.sh` |
| Migrate with stack stopped | `mobsf/mobsf_update.sh` v0.1.1 |
| smali verify nullglob guard | `lib/android.sh` |
| log_engine `--lines`/`--max-mb` validation | `system/log_engine.sh` v0.2.2 |
| Rebuild step totals + dry-run log | `fedora_rebuild.sh` v0.4.2 |
| Rebuild soft-fail + failure summary | `fedora_rebuild.sh` v0.4.5, `kali_rebuild.sh` v0.1.2 |
| Menu soft-fail, breadcrumbs, repeat, scroll | `lib/menu.sh` (Fedora v0.3.1, Kali v0.2.1) |
| Kali menu grouping + Android doctor dedup | `kali.sh` v0.2.1 |
| backup plain-root guard | `system/backup_state.sh`, `lib/common.sh` |
| RE wrapper writes without `bash -lc` | `lib/android_re.sh` v0.1.2 |
| Tighter MobSF orphan path filter | `mobsf/lib/podman.sh` |

---

## Architecture

### Dependency graph (no cycles)

```text
common.sh
├── packages.sh, health.sh, logging.sh, android.sh, research.sh
├── android_re.sh → packages.sh, android.sh
├── services.sh → health.sh
└── mobsf/lib/mobsf.sh → config, paths, podman, compose, stack, doctor

lib/mobsf.sh (shim) → mobsf/lib/mobsf.sh  [same FEDORA_MOBSF_LIB_LOADED guard]
```

**Strengths:** Idempotent load guards on top-level libs; thin task scripts; MobSF lane-local library is well-factored.

**Weaknesses:** MobSF submodules lack individual load guards; dead `services_mobsf_containers()` removed — audit was stale.

---

## Lane-by-lane code review

### Launchers

#### `fedora.sh` v0.4.0

| Item | Detail |
|------|--------|
| `fedora.sh` v0.5.2 | Lane picker; lanes return on exit; `--doctor`, rebuild flags |
| Done | `./fedora.sh 1`–`4` opens lane directly (**fixed** v0.5.2) |
| Low | Legacy menu still reads `legacy/README.md` only (no script exec) |

#### `fedora_rebuild.sh` v0.3.2

| Item | Detail |
|------|--------|
| `fedora_rebuild.sh` v0.4.2 | 5 core steps; RE install consolidated; ends with research doctor |
| Done | Step counter pre-computes total (**fixed** v0.4.2) |
| Done | `--dry-run --log` writes to fedora_rebuild.log (**fixed** v0.4.2) |
| Medium | `set -e` aborts entire rebuild on first step failure — no partial summary |

---

### `system/`

| Script | Critical/High | Medium/Low |
|--------|---------------|------------|
| `research_doctor.sh` | — | **Merged** orchestration → `lib/research.sh` |
| `view_logs.sh` | ~~`--tail --file` misparsed~~ **fixed** | **Thin shim** → `logging_view_logs_legacy()` |
| `backup_state.sh` | ~~`${HOME}` under sudo~~ **fixed** | ~~Help should warn “run as user, not sudo”~~ **fixed** — `require_invoker_user` |
| `log_engine.sh` | — | ~~Options must precede command~~ **fixed**; ~~trailing `--lines` crash~~ **fixed** v0.2.2 |
| `cleanup.sh` | — | ~~`--all-logs` ignored without `--truncate-logs`~~ **fixed** — implies truncate |
| `system_update.sh` | — | Mixes `log_*` and raw `echo` |
| `system_info.sh` | — | **Merged** → `health_print_system_info()` |
| `system_monitor.sh` | — | **Merged metrics** via `health.sh`; TUI/dashboard layout local; has `--help` |

---

### `dev/`

| Script | Critical/High | Medium/Low |
|--------|---------------|------------|
| `phpmyadmin_setup.sh` | ~~Remote by default~~ **fixed** | Re-run now restores localhost (**fixed** v0.3.1) |
| `lamp_python_setup.sh` | ~~Public info.php by default~~ **fixed** — opt-in `--with-info-php` | `--remove-info-php` in menu |
| `git_setup.sh` | ~~Hardcoded identity~~ **fixed** — env/prompt | — |
| `install_vscode.sh` | — | Overwrites repo file without backup |
| `fedora_container_kvm_setup.sh` | — | Enables docker even if package install skipped |
| `web_stack_doctor.sh` | — | Has `--help` |

---

### `android/`

| Script | Critical/High | Medium/Low |
|--------|---------------|------------|
| `android_dev_core_setup.sh` | ~~SDK temp owned by root~~ **fixed**; ~~npm as root~~ **fixed** | Pinned SDK zip URL; no upgrade path |
| `lib/android.sh` | ~~dex2jar partial verify passed~~ **fixed** | `bash -lc` in verify may hit BASH_ENV issues |
| `android_re_*_user_install.sh` | — | **Exec shims** → `android_re_install.sh`; logic in `lib/android_re.sh` |
| `verify_*.sh` | — | **Exec shims** → `verify_re_tool.sh` |
| `doctor_android_research.sh` | — | MobSF only with `--with-mobsf` (document in menu) |

**RE installer pattern consistency:** All four follow packages+android, `--help`, `post_verify`, idempotent guard. Dex2jar has extra symlink repair (justified).

---

### `mobsf/`

| Area | Critical/High | Medium/Low |
|------|---------------|------------|
| `podman.sh` | ~~Cleanup removed ALL compose containers~~ **fixed** | Start menu uses unnecessary sudo |
| `paths.sh` | ~~`chmod 0777`~~ **fixed** — default `0770` | `MOBSF_DATA_DIR_MODE` override documented |
| `compose/docker-compose.yml` | ~~Ports on `0.0.0.0`~~ **fixed** to 127.0.0.1 | Hardcoded `POSTGRES_PASSWORD=password` |
| `compose.sh` | — | ~~Validates anti-`:U` but not `:Z`~~ **fixed** |
| `mobsf_update.sh` | — | ~~Migrate against live stack~~ **fixed** v0.1.1 — down, postgres, migrate, up |
| CLI scripts | — | start/stop/doctor/status lack logging sessions |

---

### `legacy/`

| Script | Risk | Status |
|--------|------|--------|
| `FedoraInstallApps.sh` | yum + wrong package names | **Hard exit 1** |
| `setup_dev_env.sh` | system-wide pip (PEP 668) | **Hard exit 1** |
| `update_fedora.sh` | unlogged dnf, no lock wait | **Hard exit 1** |
| `verify_smali_install.sh` | duplicate logic | **Hard exit 1** |

All lacked `set -euo pipefail` except verify copy.

---

## Shared libraries — API notes

### `lib/common.sh` v0.2.1

- `real_user`, `real_home`, `run_as_real_user` — used correctly in most root scripts
- `ensure_user_bin_on_path` — managed bashrc markers (good idempotency)

### `lib/packages.sh` v0.2.1

- DNF lock wait, batch install, optional packages — production quality
- `dnf_distro_sync || true` swallows failures by design

### `lib/health.sh` v0.2.0

- `health_quick_snapshot` is alias for `health_post_update_snapshot` (redundant export)

### `lib/logging.sh` v0.3.1

- `FEDORA_LOG_MOBSF="mobsf.log"` · `logging_view_logs_legacy()` for deprecated shim

### `lib/services.sh` v0.2.4

- `services_status_research_stack()` includes MobSF via `services_mobsf_brief`

### `lib/android.sh` v0.2.3

- `android_verify_as_user` uses explicit `HOME` + `PATH` (no login shell)

---

## Security matrix

| Finding | Severity | Location | Recommendation |
|---------|----------|----------|----------------|
| phpMyAdmin remote by default | High | `dev/phpmyadmin_setup.sh` | **Fixed** — `--allow-remote` opt-in |
| Public `info.php` by default | High | `dev/lamp_python_setup.sh` | **Fixed** — `--with-info-php` opt-in |
| Hardcoded git PII | High | `dev/git_setup.sh` | **Fixed** — env/prompt |
| MobSF data dirs `0777` | High | `mobsf/lib/paths.sh` | **Fixed** — default `0770`; `MOBSF_DATA_DIR_MODE=0777` override |
| Compose DB password | Medium | `docker-compose.yml` | Generate to `~/MobSF/.env` at install |
| LAN-visible ports | High | compose | **Fixed** — bind 127.0.0.1 |
| Orphan cleanup scope | Critical | `podman.sh` | **Fixed** — MobSF working_dir filter |
| Legacy scripts runnable | Critical | `legacy/` | **Fixed** — exit 1 guards |
| No `eval` / `curl\|bash` | — | All active scripts | Clean |

---

## Logging coverage matrix

| Always logs | Optional / never |
|-------------|------------------|
| `system_update.sh` | All RE installers |
| `android_dev_core_setup.sh` | mobsf start/stop/doctor/status |
| mobsf install/reset/update | dev scripts |
| `fedora_rebuild.sh --log` | rebuild child steps (stdout teed only) |

---

## `--help` coverage

**Has `--help`:** all lane launchers, system ops (info, monitor, research_doctor, log_engine, view_logs), dev stack scripts, MobSF CLI (incl. status), `android_re_install.sh`, `verify_re_tool.sh`, doctors, cleanup, backup, kvm setup, android core setup

**Missing `--help` (low priority):** none — all active task scripts covered.

---

## Code quality conventions

| Convention | Compliance |
|------------|------------|
| `#!/usr/bin/env bash` | All active scripts (legacy uses `#!/bin/bash`) |
| `set -euo pipefail` | All active; legacy disabled before body |
| Version in header | 39/41 task scripts (`system_monitor` missing) |
| `# shellcheck source=` hints | Lib consumers — good |
| Lib modules not executable | Correct (`644`) |
| Task scripts executable | Mostly `755`; launcher uses `bash` anyway |

---

## Recommended remediation (remaining)

### P1 — Security & correctness

1. ~~MobSF data dir permissions~~ **Done** (0770 default)
2. ~~`android_verify_as_user` HOME/PATH~~ **Done**

### P2 — UX & consistency

1. ~~`log_engine.sh` global options before command~~ **Done** (v0.2.1)
2. ~~Menu soft-fail, breadcrumbs, repeat, scroll mode~~ **Done** — see [AUDIT-UX.md](AUDIT-UX.md)
3. ~~Rebuild continue-on-failure + summary~~ **Done** (v0.4.5 / v0.1.2)
4. RE installer `--upgrade` flag

### P3 — Enhancements

1. Generate compose secrets at install time
2. User systemd unit for MobSF autostart on login
3. Add shellcheck to CI / pre-commit

---

## Test checklist (post-fix)

```bash
# Syntax + shellcheck
find . -name '*.sh' ! -path './legacy/*' -type f -exec bash -n {} +
find . -name '*.sh' ! -path './legacy/*' -type f -print0 | xargs -0 shellcheck -S warning

# Critical paths
./system/research_doctor.sh --help
./system/research_doctor.sh --android-only
./system/view_logs.sh --file system_update.log --tail 5
./legacy/update_fedora.sh   # must exit 1

# Android verify
./android/verify_dex2jar_install.sh   # should fail if any d2j-* missing

# MobSF cleanup (dry review — lists skips for non-MobSF)
./mobsf/mobsf_cleanup.sh
```

---

## Conclusion

The codebase is **well-structured for a personal ops toolkit** with thin root/lane launchers and strong lib adoption. Major consolidation (RE install, verify CLIs, health metrics, research doctor, view_logs shim, lane READMEs) is **done**. Remaining work is mostly MobSF hardening and minor UX polish.

See [AUDIT.md](AUDIT.md) · [AUDIT-UX.md](AUDIT-UX.md) · [CONSOLIDATION.md](CONSOLIDATION.md)
