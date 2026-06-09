# Fedora Workstation Control Plane

**fedora-linux-scripts** — Fedora workstation **setup, readiness, stabilization, and repair** for Android security research (**neptune** and similar hosts). Not Mercury (no database backup, DR manifests, or prod-to-dev sync).

Also known as the **Fedora Rebuild Kit** for guided install flows.

| Entry | Use |
|-------|-----|
| **`./run.sh`** | Main menu — setup lanes, workstation readiness, rebuild |
| **`./setup.sh`** | Repo/toolkit readiness (validate · optional smoke) |
| **`./mobsf.sh`** | MobSF stack — install/start/**doctor** (separate lifecycle) |
| **`./fedora.sh`** | Compatibility wrapper → `./run.sh` (older docs/scripts) |
| **`./fedora_rebuild.sh`** | Rebuild engine · compat → `./run.sh --rebuild` |

```bash
./setup.sh            # first-run repo check (no sudo · no installs)
./run.sh              # interactive menu
./run.sh --check      # validate + smoke + rebuild readiness (start here)
./run.sh --check --fix-repos   # fix DNF repos (sudo) then re-check
./run.sh --check --full        # + full smoke + Fedora doctor
./run.sh --daily-driver-check  # read-only daily driver / stabilization report
./run.sh --doctor     # Fedora doctor (repo · lanes · workstation health)
./run.sh --baseline   # fresh-install host baseline → logs/
./run.sh --rebuild-check   # pre-rebuild readiness only
./run.sh --rebuild    # guided full setup
./run.sh --smoke      # dynamic CLI/menu tests
./run.sh --fix-repos  # fix DNF .repo permissions (sudo)
./mobsf.sh --doctor      # MobSF stack health (separate)
```

**Start here:** [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md) · **Docs index:** [docs/README.md](docs/README.md)

---

## Layout

```text
fedora-linux-scripts/
├── README.md · docs/ · validate.sh
├── run.sh · setup.sh · fedora.sh (compat) · mobsf.sh · fedora_rebuild.sh
├── lib/                 ← shared libraries
├── system/ · dev/ · android/
├── mobsf/               ← Podman stack (see mobsf/GUIDE.md)
├── legacy/              ← disabled reference only
└── logs/
```

Shared libs: `common`, `theme`, `menu`, `packages`, `health`, `android`, `android_re`, `research`, `services`, `logging`.

---

## Two identities

| Identity | Purpose |
|----------|---------|
| **Setup / rebuild lanes** | Install and configure: system, dev, desktop, virt, web, Android RE; MobSF separate |
| **Readiness / stabilization** | Daily driver, btrfs/LUKS/vbox checks, package noise, post-update validation, recovery export |

Workstation readiness: `./run.sh --daily-driver-check` or System menu → **Daily driver check** `[1]`.

---

## Lanes

| Area | Folder | Guide |
|------|--------|-------|
| System maintenance | `system/` | [system/README.md](system/README.md) |
| Developer workstation areas | `dev/` | [dev/README.md](dev/README.md) |
| Android RE tools entry | `android/` | [android/README.md](android/README.md) |
| MobSF *(separate)* | `mobsf/` | [mobsf/GUIDE.md](mobsf/GUIDE.md) |
| Legacy | `legacy/` | [legacy/README.md](legacy/README.md) |

---

## Install (summary)

Full path: **`./run.sh --rebuild`**. Manual order and doctor matrix: [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md).

MobSF optional: `./mobsf.sh install` → [mobsf/GUIDE.md](mobsf/GUIDE.md)

---

## Script index

### Launchers

| Script | Purpose |
|--------|---------|
| `run.sh` | Main workstation entry |
| `setup.sh` | Lightweight repo readiness helper |
| `fedora.sh` | Compatibility wrapper → `run.sh` |
| `mobsf.sh` | MobSF wrapper → `mobsf/mobsf.sh` |
| `fedora_rebuild.sh` | Rebuild engine + compat redirect |
| `system/system.sh` · `dev/dev.sh` · `android/android.sh` | Lane menus + CLI |
| `validate.sh` | Syntax, entry points, ShellCheck; `--smoke` runs smoke_test |
| `smoke_test.sh` | Dynamic CLI/menu smoke tests (read-only) |

### System

| Script | Purpose |
|--------|---------|
| `daily_driver_check.sh` | Read-only daily driver report (`./run.sh --daily-driver-check`) |
| `btrfs_health.sh` | Btrfs stats/scrub; `--scrub` starts scrub (confirm) |
| `luks_readiness.sh` | LUKS keyslots, header backups; `--add-passphrase` (sudo · interactive) |
| `virtualbox_readiness.sh` | vbox modules, vboxdrv, packages |
| `package_noise.sh` | PackageKit/dnf/flatpak noise; `--stop-session` |
| `post_update_check.sh` | After `dnf upgrade`: reboot, btrfs, services, vbox |
| `system_update.sh` | Full Fedora update + health snapshot; `--quick` skips rpm -Va |
| `fresh_install_check.sh` | Host baseline after fresh install (`./run.sh --baseline`) |
| `rebuild_readiness_check.sh` | Pre-rebuild checks (`./run.sh --rebuild-check`) |
| `system_info.sh` · `system_monitor.sh` | Snapshot · live dashboard |
| `research_doctor.sh` | Full research doctor (Android + MobSF); Fedora doctor uses `--android-only` |
| `log_engine.sh` | Logs CLI |
| `view_logs.sh` | Shim → `log_engine.sh` |
| `backup_state.sh` · `cleanup.sh` | Pre-reinstall export · DNF/log cleanup |

### Dev

| Script | Purpose |
|--------|---------|
| `git_setup.sh` · `install_vscode.sh` · `desktop_setup.sh` | Git · VS Code · [Cinnamon `@cinnamon-desktop`](dev/README.md#desktop-environments-cinnamon) |
| `fedora_container_kvm_setup.sh` | Podman, Docker, KVM |
| `lamp_python_setup.sh` · `phpmyadmin_setup.sh` | LAMP · phpMyAdmin |
| `web_stack_doctor.sh` | LAMP/phpMyAdmin checks |

### Android

| Script | Purpose |
|--------|---------|
| `android_dev_core_setup.sh` | Java, SDK, Frida, ADB, pip tools |
| `android_re_install.sh` | RE tools (apktool/jadx/smali/dex2jar/all, `--upgrade`) |
| `verify_re_tool.sh` | Verify one or all |
| `doctor_android_research.sh` | Android doctor (`--with-mobsf`) |
| `android_re_*_user_install.sh` · `verify_*_install.sh` | Shims → preferred scripts above |

### MobSF

| Script | Purpose |
|--------|---------|
| `mobsf_install.sh` · `mobsf_reset.sh` · `mobsf_update.sh` | Bootstrap · reset · pull+migrate |
| `mobsf_doctor.sh` | Readiness (`--dynamic`) |
| `mobsf_start.sh` · `mobsf_stop.sh` · `mobsf_status.sh` | Stack control |
| `mobsf_logs.sh` · `mobsf_autostart.sh` · `mobsf_cleanup.sh` | Logs · systemd · orphans |

Details: [mobsf/GUIDE.md](mobsf/GUIDE.md) · [mobsf/STACK.md](mobsf/STACK.md) · [mobsf/TROUBLESHOOTING.md](mobsf/TROUBLESHOOTING.md)

---

## Conventions

- Scripts use `set -euo pipefail`, idempotent re-runs where practical.
- Android RE installs → `~/.local/opt/` + `~/.local/bin/`; use `--upgrade` to re-fetch.
- Logging: [logs/README.md](logs/README.md) · `./system/log_engine.sh`
- CI: `.github/workflows/validate.yml` runs `./validate.sh --shellcheck`

---

## Requirements

Fedora 43+ · `sudo` · network · Java 21 for RE tools

---

## Documentation

| Doc | Purpose |
|-----|---------|
| [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md) | Onboarding, doctors, rebuild |
| [docs/RECOVERY.md](docs/RECOVERY.md) | Btrfs · LUKS · boot · VirtualBox recovery |
| [docs/AUDIT.md](docs/AUDIT.md) | Maintainer audit (security, menus, QA) |
| [logs/README.md](logs/README.md) | Logging engine |
