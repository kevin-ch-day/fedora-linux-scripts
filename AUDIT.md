# Fedora Toolkit Audit

**Repo:** `fedora-linux-scripts`  
**Target machine:** neptune (Fedora Android security research workstation)  
**Audit date:** 2026-06-07 (updated post-consolidation)  
**Status:** As-built audit — lane picker v0.5.1, lane launchers, shared libs

---

## Executive summary

This repo is a **mature ops-grade toolkit** with a thin root launcher, four lane launchers, shared libraries, structured logging, and legacy reference scripts.

| Metric | Count |
|--------|------:|
| Task shell scripts (excl. lib/menu modules) | **~45** active + **4** legacy |
| Shared lib modules (`lib/` + `mobsf/lib/`) | **15** |
| Lane menu modules (`*/lib/menu.sh`) | **4** |
| Markdown docs | **11+** |

**Architecture (as built):**

```text
fedora.sh (v0.4)              ← thin router → lane menus + rebuild
fedora_rebuild.sh (v0.3.2)    ← guided sequence
lib/                          ← cross-lane shared libs (+ android_re.sh)
system/system.sh              ← system/lib/menu.sh
dev/dev.sh                    ← dev/lib/menu.sh
android/android.sh            ← android/lib/menu.sh
mobsf/mobsf.sh                ← mobsf/lib/menu.sh
legacy/                       ← hard-disabled reference only
logs/                         ← operational logs + README policy
```

**Health:** Active scripts pass `bash -n` and ShellCheck `-S warning`. Deep review: **[AUDIT-CODE.md](AUDIT-CODE.md)**. Merge map: **[CONSOLIDATION.md](CONSOLIDATION.md)**.

**Recent consolidation:** `fedora.sh` slimmed; RE install logic in `lib/android_re.sh`; verify/install CLIs; `system_monitor` + `system_info` use `lib/health.sh`; dev security defaults (phpMyAdmin localhost, opt-in phpinfo).

---

## Directory map

```text
fedora-linux-scripts/
├── fedora.sh                 v0.4.0  Thin router → lane menus
├── fedora_rebuild.sh         v0.3.2  Guided rebuild (5 core steps + optional)
├── CONSOLIDATION.md                  Merge / entry-point map
├── README.md                         Toolkit index
├── AUDIT.md                          This file
├── lib/
│   ├── common.sh             v0.2.1  Foundation
│   ├── menu.sh               v0.1.1  TUI menus (all lanes)
│   ├── packages.sh           v0.2.1  DNF/RPM helpers
│   ├── health.sh             v0.2.2  Host metrics + health_print_system_info
│   ├── android.sh            v0.2.2  RE verify, ADB, doctor
│   ├── android_re.sh         v0.1.0  RE user-scope install engine
│   ├── services.sh           v0.2.3  systemctl, web/MobSF status
│   ├── logging.sh            v0.3.1  Logging engine + legacy view_logs mapping
│   ├── research.sh           v0.1.0  Combined research doctor
│   └── mobsf.sh              v0.2.0  Shim → mobsf/lib/mobsf.sh
├── system/system.sh          v0.1.0  System lane launcher
├── dev/dev.sh                v0.1.0  Dev lane launcher
├── android/android.sh        v0.1.0  Android lane launcher
├── mobsf/mobsf.sh            v0.1.0  MobSF lane launcher
├── legacy/                   Hard-disabled scripts + README
└── logs/                     README policy; runtime *.log gitignored
```

---

## Shared libraries

### `lib/` (cross-lane)

| Module | Version | Role | Sourced by |
|--------|---------|------|------------|
| `common.sh` | 0.2.1 | `info/ok/warn/die`, `real_user`, `run_as_real_user`, `ensure_user_bin_on_path`, `user_add_supplementary_group` | All libs; most task scripts via other libs |
| `menu.sh` | 0.1.1 | TUI headers, `menu_loop`, script runners | All lane launchers, `fedora.sh` |
| `packages.sh` | 0.2.1 | DNF install, batch, optional, kernel prune | system_update, cleanup, dev, android core |
| `health.sh` | 0.2.2 | CPU/RAM/disk/network, `health_print_system_info`, monitor metrics | system_info, system_monitor, system_update, backup_state, system/lib/menu.sh |
| `android.sh` | 0.2.2 | RE verify, ADB, `doctor_android_research`, GitHub helpers | verify_re_tool, doctors |
| `android_re.sh` | 0.1.0 | RE user-scope install (apktool/jadx/smali/dex2jar) | android_re_install.sh, per-tool shims |
| `services.sh` | 0.2.3 | systemctl, LAMP stack, MobSF container listing | dev doctors, kvm, lane menus |
| `logging.sh` | 0.3.1 | `init_script_logging`, log_engine, `logging_view_logs_legacy` | system_update, mobsf ops, view_logs, fedora_rebuild --log |
| `research.sh` | 0.1.0 | `research_doctor_run` | research_doctor.sh |
| `mobsf.sh` | 0.2.0 | Back-compat re-export | fedora_rebuild (MobSF step) |

### `mobsf/lib/` (lane-local)

| Module | Role |
|--------|------|
| `mobsf.sh` | Loader |
| `config.sh` | UI URLs, bundle dir |
| `paths.sh` | `~/MobSF/` paths, `mobsf_compose_installed` |
| `podman.sh` | `mobsf_pc/pd`, container discovery, orphan cleanup, HTTP check |
| `compose.sh` | Deploy Fedora bundle, validate guardrails |
| `stack.sh` | install, reset, ordered up/down |
| `doctor.sh` | Full doctor + `mobsf_doctor_brief` |

---

## Script inventory

Legend: **Op** = operational, **Ins** = installer, **Ver** = verify, **Diag** = diagnostic, **Orch** = orchestrator  
**Log** = uses `init_script_logging` · **Help** = has `--help`

### Launchers

| Script | Ver | Cat | Sudo | Libs | Log | Help | Menu / CLI |
|--------|-----|-----|------|------|-----|------|------------|
| `fedora.sh` | 0.4.0 | Op | Maybe | menu | — | Yes | Thin router; `--doctor`, `--rebuild*` |
| `fedora_rebuild.sh` | 0.3.2 | Orch | Maybe | common, logging, mobsf | opt `--log` | Yes | fedora [5] rebuild submenu |
| `system/system.sh` | 0.1.0 | Op | Maybe | system/lib/menu | — | Yes | System lane; CLI shortcuts |
| `dev/dev.sh` | 0.1.0 | Op | Maybe | dev/lib/menu | — | Yes | Dev lane; CLI shortcuts |
| `android/android.sh` | 0.1.0 | Op | Maybe | android/lib/menu | — | Yes | Android lane |
| `mobsf/mobsf.sh` | 0.1.0 | Op | Maybe | mobsf/lib/menu | — | Yes | MobSF lane |

### `system/`

| Script | Ver | Cat | Sudo | Libs | Log | Help | Menu |
|--------|-----|-----|------|------|-----|------|------|
| `system_update.sh` | 0.5.7 | Op | Yes | packages, health, logging | Yes | Yes | system lane → Maintenance [1] |
| `system_info.sh` | 0.5.0 | Op | No | health | — | Yes | system lane → Host [1] |
| `system_monitor.sh` | 0.1.1 | Op | No | health | — | Yes | system lane → Host [2] |
| `research_doctor.sh` | 0.2.0 | Diag | No | research | — | Yes | system lane [4]; `fedora.sh --doctor` |
| `backup_state.sh` | 0.1.0 | Op | No | health, logging | — | Yes | system lane → Maintenance [2] |
| `cleanup.sh` | 0.3.0 | Op | Maybe | packages, logging | — | Yes | system lane → Maintenance [3] |
| `log_engine.sh` | 0.2.0 | Op | No | logging | — | Yes | system lane → Logs |
| `view_logs.sh` | 0.5.0 | Op | No | logging | — | Yes | Deprecated shim → log_engine |

### `dev/`

| Script | Ver | Cat | Sudo | Libs | Log | Help | Menu |
|--------|-----|-----|------|------|-----|------|------|
| `git_setup.sh` | 0.3.0 | Ins | Maybe | packages | — | Yes | dev lane → Workstation |
| `install_vscode.sh` | 0.3.0 | Ins | Yes | packages | — | Yes | dev lane |
| `fedora_container_kvm_setup.sh` | 0.3.0 | Ins | Yes | packages, services | — | Yes | dev lane |
| `lamp_python_setup.sh` | 0.3.0 | Ins | Yes | packages, services | — | Yes | dev lane |
| `phpmyadmin_setup.sh` | 0.3.0 | Ins | Yes | packages, services | — | Yes | dev lane |
| `web_stack_doctor.sh` | 0.2.0 | Diag | No | services | — | Yes | dev lane → Web stack doctor |

### `android/`

| Script | Ver | Cat | Sudo | Libs | Log | Help | Menu |
|--------|-----|-----|------|------|-----|------|------|
| `android_dev_core_setup.sh` | 0.6.2 | Ins | Yes | packages, logging | Yes | Yes | android lane → Setup |
| `android_re_install.sh` | 0.2.0 | Ins | No* | android_re | — | Yes | android lane → RE installs |
| `android_re_*_user_install.sh` | — | Ins | No* | shim | — | via CLI | Exec shims → android_re_install |
| `verify_re_tool.sh` | 0.1.0 | Ver | No | android | — | Yes | android lane → Verify |
| `verify_*_install.sh` | — | Ver | No | shim | — | — | Exec shims → verify_re_tool |
| `doctor_android_research.sh` | 0.2.1 | Diag | No | android | — | Yes | android lane → Diagnostics |
| `helpers/debug_bash_env_verify_smali.sh` | 0.1.0 | Diag | No | **none** | — | No | android lane verify [6] |

\*May invoke `sudo dnf` for curl/unzip if missing.

### `mobsf/`

| Script | Ver | Cat | Sudo | Libs | Log | Help | Menu |
|--------|-----|-----|------|------|-----|------|------|
| `mobsf_install.sh` | 0.1.0 | Ins | `sudo -E` | packages, mobsf/lib, logging | Yes | Yes | MobSF [1] |
| `mobsf_doctor.sh` | 0.1.0 | Diag | No | mobsf/lib | — | Yes | MobSF [2] |
| `mobsf_start.sh` | 0.1.0 | Op | Optional | mobsf/lib | — | Yes | MobSF [3] |
| `mobsf_stop.sh` | 0.1.0 | Op | No | mobsf/lib | — | Yes | MobSF [4] |
| `mobsf_logs.sh` | 0.1.0 | Op | No | mobsf/lib | — | Yes | MobSF [5] |
| `mobsf_update.sh` | 0.1.0 | Op | `sudo -E` | mobsf/lib, logging | Yes | Yes | MobSF [6] |
| `mobsf_reset.sh` | 0.3.0 | Op | `sudo -E` | mobsf/lib, logging | Yes | Yes | MobSF [7–8] |
| `mobsf_status.sh` | 0.1.0 | Op | No | mobsf/lib | — | No | MobSF [9] |
| `mobsf_cleanup.sh` | 0.1.0 | Op | No | mobsf/lib | — | Yes | MobSF [10] |

### `legacy/` (do not use)

| Script | Replacement |
|--------|-------------|
| `update_fedora.sh` | `system/system_update.sh` |
| `setup_dev_env.sh` | `android/android_dev_core_setup.sh` |
| `FedoraInstallApps.sh` | `dev/` + `android/` scripts |
| `verify_smali_install.sh` | `android/verify_smali_install.sh` |

---

## Logging engine

| Log file | Writers | Default rotate |
|----------|---------|----------------|
| `logs/system_update.log` | `system_update.sh` | 10 MB |
| `logs/fedora_rebuild.log` | `fedora_rebuild.sh --log` | off |
| `logs/android_dev_core.log` | `android_dev_core_setup.sh` | off |
| `logs/mobsf.log` | mobsf install, reset, update | off |
| `logs/backups/` | `backup_state.sh` | — |
| `logs/archive/` | log_engine archive/rotate | — |

**Not logged (stdout only):** most android RE installers, mobsf start/stop/doctor, dev scripts, system_info/monitor.

**CLI:** `system/log_engine.sh` · deprecated shim `system/view_logs.sh` · system lane → Logs

---

## Menu coverage (v0.5.0)

| Entry | Items | Notes |
|-------|------:|-------|
| `fedora.sh` | 4 + exit | Lane picker; lanes return on [0] Back |
| `fedora_rebuild.sh` | 5 modes | Own mode menu when run interactively with no flags |
| `system/system.sh` | 4 | Host · Maintenance · Logs · Research doctor |
| `dev/dev.sh` | 3 groups | Workstation · Infrastructure · Web stack |
| `android/android.sh` | 4 | Setup · RE installs · Verify · Diagnostics |
| `mobsf/mobsf.sh` | grouped | Stack · Setup · Maintenance · Logs · Docs |

**Not in fedora.sh:** rebuild submenu, legacy (use `./fedora_rebuild.sh` and `legacy/README.md`).

See [GETTING-STARTED.md](GETTING-STARTED.md) for `fedora.sh` vs `fedora_rebuild.sh`.

---

## Duplication & outliers

| Item | Status | Recommendation |
|------|--------|------------------|
| `lib/android_re.sh` | **Done** | Single RE install engine |
| `system_monitor.sh` | **Mostly merged** | CPU/load/mem/swap/disk pct via `health.sh`; TUI layout stays local |
| `system_info.sh` | **Done** | Thin wrapper → `health_print_system_info` |
| RE/verify per-tool scripts | **Done** | Exec shims |
| `lib/mobsf.sh` shim | Keep | Back-compat for `fedora_rebuild`; prefer `mobsf/lib/` |
| `git_setup.sh` identity | Improved | Env/prompt; document in README |

---

## Documentation inventory

| Doc | Purpose | Up to date? |
|-----|---------|-------------|
| `README.md` | Toolkit index, install order, script table | Mostly yes |
| `CONSOLIDATION.md` | Entry points, doctors, merge status | **Current** |
| `AUDIT.md` | Inventory + ops snapshot | **Updated post-consolidation** |
| `AUDIT-CODE.md` | Deep code audit + security matrix | **New 2026-06-07** |
| `logs/README.md` | Logging policy + log_engine CLI | Yes |
| `legacy/README.md` | Legacy replacements | Yes |
| `mobsf/README.md` | MobSF hub | Yes |
| `mobsf/INSTALL.md` | First-time install | Yes |
| `mobsf/OPERATIONS.md` | Day-to-day ops | Yes |
| `mobsf/STACK.md` | Architecture / ports | Yes |
| `mobsf/TROUBLESHOOTING.md` | Fedora/SELinux fixes | Yes |
| `mobsf/lib/README.md` | Lane-local lib modules | Yes |

**Missing docs (optional):** none — lane guides: [system/README.md](system/README.md), [dev/README.md](dev/README.md), [android/README.md](android/README.md).

---

---

## Gaps & recommendations (prioritized)

### P0 — Operational (neptune)

1. **Run MobSF install** if stack down:
   ```bash
   sudo -E ./mobsf/mobsf_install.sh
   ./system/research_doctor.sh
   ```

### P1 — High ROI polish

1. ~~Lane README stubs~~ **Done** (`system/`, `dev/`, `android/`)
2. MobSF install on neptune if stack down

### P2 — Structural

1. `system_monitor.sh` TUI layout only (metrics merged into `health.sh`)
2. Auto-rotate default for large logs

### P3 — Nice to have

1. MobSF autostart systemd user unit
2. MobSF dynamic analysis setup script

## Neptune host notes (2026-06-07)

| Check | State |
|-------|-------|
| Podman / podman-compose | Installed |
| SELinux | Enforcing |
| `~/MobSF/compose/` | Deployed (Fedora bundle) |
| MobSF containers | Removed via `mobsf_cleanup.sh` (was stale `docker_*_1` set) |
| MobSF UI :8080 | Not running — needs install/start |
| Android RE tools | Verified working (prior session) |
| `logs/system_update.log` | ~614 KB, pre-v0.3 session format |

---

## Classification summary

| Lane | Scripts | Lib-adopted | Standalone |
|------|--------:|------------:|-----------:|
| system | 9 | 8 | 1 (research_doctor orchestrator) |
| dev | 6 | 6 | 0 |
| android | 14 | 13 | 1 (debug helper) |
| mobsf | 9 | 9 | 0 |
| launchers | 6 | 6 | 0 |
| legacy | 4 | 0 | 4 |
| **Total** | **~48** | **~42** | **~6** |

---

## Conclusion

The Fedora toolkit matches the intended architecture: **thin root launcher + lane launchers + shared libs + focused task scripts**. Consolidation pass merged RE installs, verify/install CLIs, health metrics, and host snapshots.

**Deep code audit:** [AUDIT-CODE.md](AUDIT-CODE.md) · **Merge map:** [CONSOLIDATION.md](CONSOLIDATION.md)

Primary follow-ups: **MobSF install on neptune**, optional **lane README** stubs.

For day-to-day use:

```bash
./fedora.sh                    # lane picker (lanes return on [0])
./fedora.sh 3                  # Android lane once
./fedora_rebuild.sh            # full setup
./fedora.sh --doctor           # Android + MobSF readiness
```
