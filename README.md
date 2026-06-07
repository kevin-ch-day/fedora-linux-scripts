# Fedora Rebuild Kit

**fedora-linux-scripts** — Fedora workstation automation for Android security research (**neptune** and similar hosts).

| Entry | Use |
|-------|-----|
| **`./fedora.sh`** | Main menu — lanes; rebuild `[4]`; doctor `[5]`; toolkit check `[6]` |
| **`./mobsf.sh`** | MobSF stack — install/start/**doctor** (separate lifecycle) |
| **`./fedora_rebuild.sh`** | Compatibility → `./fedora.sh --rebuild` |

```bash
./fedora.sh              # interactive menu
./fedora.sh --check      # validate + smoke + rebuild readiness (start here)
./fedora.sh --check --fix-repos   # fix DNF repos (sudo) then re-check
./fedora.sh --check --full        # + full smoke + Fedora doctor
./fedora.sh --doctor     # Fedora doctor (repo · lanes · workstation health)
./fedora.sh --baseline   # fresh-install host baseline → logs/
./fedora.sh --rebuild-check   # pre-rebuild readiness only
./fedora.sh --rebuild    # guided full setup
./fedora.sh --smoke      # dynamic CLI/menu tests
./fedora.sh --fix-repos  # fix DNF .repo permissions (sudo)
./mobsf.sh --doctor      # MobSF stack health (separate)
```

**Start here:** [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md) · **Docs index:** [docs/README.md](docs/README.md)

---

## Layout

```text
fedora-linux-scripts/
├── README.md · docs/ · validate.sh
├── fedora.sh · mobsf.sh · fedora_rebuild.sh
├── lib/                 ← shared libraries
├── system/ · dev/ · android/
├── mobsf/               ← Podman stack (see mobsf/GUIDE.md)
├── legacy/              ← disabled reference only
└── logs/
```

Shared libs: `common`, `theme`, `menu`, `packages`, `health`, `android`, `android_re`, `research`, `services`, `logging`.

---

## Lanes

| Lane | Folder | Guide |
|------|--------|-------|
| System | `system/` | [system/README.md](system/README.md) |
| Dev | `dev/` | [dev/README.md](dev/README.md) |
| Android RE | `android/` | [android/README.md](android/README.md) |
| MobSF *(separate)* | `mobsf/` | [mobsf/GUIDE.md](mobsf/GUIDE.md) |
| Legacy | `legacy/` | [legacy/README.md](legacy/README.md) |

---

## Install (summary)

Full path: **`./fedora.sh --rebuild`**. Manual order and doctor matrix: [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md).

MobSF optional: `./mobsf.sh install` → [mobsf/GUIDE.md](mobsf/GUIDE.md)

---

## Script index

### Launchers

| Script | Purpose |
|--------|---------|
| `fedora.sh` | Main entry |
| `mobsf.sh` | MobSF wrapper → `mobsf/mobsf.sh` |
| `fedora_rebuild.sh` | Rebuild compat wrapper |
| `system/system.sh` · `dev/dev.sh` · `android/android.sh` | Lane menus + CLI |
| `validate.sh` | Syntax, entry points, ShellCheck; `--smoke` runs smoke_test |
| `smoke_test.sh` | Dynamic CLI/menu smoke tests (read-only) |

### System

| Script | Purpose |
|--------|---------|
| `system_update.sh` | Full Fedora update + health snapshot; `--quick` skips rpm -Va |
| `fresh_install_check.sh` | Host baseline after fresh install (`./fedora.sh --baseline`) |
| `rebuild_readiness_check.sh` | Pre-rebuild checks (`./fedora.sh --rebuild-check`) |
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
| [docs/AUDIT.md](docs/AUDIT.md) | Maintainer audit (security, menus, QA) |
| [logs/README.md](logs/README.md) | Logging engine |
