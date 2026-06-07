# Fedora Rebuild Kit

**fedora-linux-scripts** — a standalone repo for Fedora workstation automation.

This is the **Fedora workstation rebuild and maintenance toolkit**: scripts to bring a fresh or upgraded Fedora install back to a known-good state. It covers system maintenance, development setup, Android security / reverse-engineering tooling, web/database stack, containers, virtualization, and MobSF.

**Primary target:** **neptune** and future Fedora machines used for Android security research.

**Entry point:** `./fedora.sh` — lane picker (exit a lane to return; use `./fedora.sh 1`–`4` for one-shot).

### `fedora.sh` vs `fedora_rebuild.sh`

| Script | When to use |
|--------|-------------|
| **`./fedora.sh`** | Day-to-day: pick a lane menu (updates, dev tools, Android RE, MobSF). |
| **`./fedora_rebuild.sh`** | Rarely: guided **full** setup after fresh install or major upgrade (update → KVM → Android core → RE tools → verify → optional MobSF → doctor). |

Same rebuild without the lane picker: `./fedora.sh --rebuild` or `./fedora_rebuild.sh --yes`.

**Legacy:** `legacy/` is disabled reference only — not in any menu.

---

## Repository layout

```text
fedora-linux-scripts/   ← this repo (Fedora-only rebuild kit)
├── fedora.sh           ← lane picker (System / Dev / Android / MobSF)
├── fedora_rebuild.sh   ← guided full rebuild (separate)
├── lib/                ← shared libraries
├── system/
├── dev/
├── android/
├── mobsf/
├── legacy/
└── logs/
```

**Libraries:** `lib/common.sh`, `lib/errors.sh`, `lib/menu.sh`, `lib/packages.sh`, `lib/health.sh`, `lib/android.sh`, `lib/android_re.sh`, `lib/research.sh`, `lib/services.sh`, and `lib/logging.sh`.

**Entry points:** `./fedora.sh` (lane picker), `./fedora_rebuild.sh` (full rebuild). See [GETTING-STARTED.md](GETTING-STARTED.md). Lane menus: `./system/system.sh`, `./dev/dev.sh`, `./android/android.sh`, `./mobsf/mobsf.sh`.

---

## Lanes

| Lane | Folder | What it covers |
|------|--------|----------------|
| System maintenance | `system/` | Updates, monitoring, logs — [system/README.md](system/README.md) |
| Developer workstation | `dev/` | Git, VS Code, LAMP, phpMyAdmin, Podman/KVM — [dev/README.md](dev/README.md) |
| Android security research | `android/` | ADB, SDK, Frida, RE tools — [android/README.md](android/README.md) |
| MobSF | `mobsf/` | Rootless Podman stack reset/rebuild |
| Legacy | `legacy/` | Superseded scripts (kept for reference) |

The **Android** lane is first-class: it directly supports research on ScytaleDroid, ObsidianDroid, Iapetus, Permission Intel, MobSF triage, and dynamic analysis workflows. See [android/README.md](android/README.md).

---

## Directory layout

```text
fedora-linux-scripts/
├── README.md
├── AUDIT.md
├── GETTING-STARTED.md         ← fedora.sh vs fedora_rebuild.sh (start here)
├── fedora.sh                  ← lane picker (4 lanes)
├── fedora_rebuild.sh          ← guided full rebuild
├── lib/
│   ├── common.sh              ← shared helpers (foundation)
│   ├── menu.sh                ← interactive TUI menus (all lanes)
│   ├── packages.sh            ← dnf/rpm package helpers
│   ├── health.sh              ← host health and snapshot helpers
│   ├── android.sh             ← RE verify, ADB, doctor, GitHub helpers
│   ├── android_re.sh          ← RE user-scope install logic (shared)
│   ├── research.sh            ← combined research doctor orchestration
│   ├── services.sh            ← systemctl / service status
│   └── logging.sh             ← logging engine (write + read + maintenance)
├── fedora_rebuild.sh          ← guided full rebuild sequence
├── system/
├── dev/                # Developer workstation setup
├── android/            # Android security / RE tooling (centerpiece)
├── mobsf/              # MobSF Podman stack management
├── legacy/             # Deprecated scripts (reference only)
└── logs/               # Append-only logs (e.g. system_update.log)
```

---

## Recommended install order

**Full guided path:** `./fedora_rebuild.sh` (or `./fedora.sh --rebuild`).

**Daily menus:** `./fedora.sh` → pick a lane. See [GETTING-STARTED.md](GETTING-STARTED.md).

Run from the repo root unless noted.

### 1. System baseline

```bash
sudo ./system/system_update.sh
```

### 2. Containers and virtualization

```bash
sudo ./dev/fedora_container_kvm_setup.sh
```

### 3. Core Android security workstation

```bash
sudo ./android/android_dev_core_setup.sh
```

Installs Java 21, ADB/Fastboot, Android SDK cmdline-tools, Frida, Objection, Drozer, Mitmproxy, Wireshark, Node/npm, and optional Android Studio (Flatpak).

### 4. Reverse-engineering tools (user scope)

```bash
./android/android_re_install.sh all
# or one at a time: apktool | jadx | smali | dex2jar
```

After install, reload your shell or run `source ~/.bashrc`.

### 5. Verify RE tooling

```bash
./android/verify_re_tool.sh all
./android/doctor_android_research.sh   # Android-only; use research_doctor.sh for MobSF too
```

### 6. MobSF (optional)

First-time install (Fedora/Podman/SELinux-safe bundle):

```bash
sudo -E ./mobsf/mobsf_install.sh
./mobsf/mobsf_doctor.sh
```

Stack lives at `~/MobSF/compose/`; UI at **http://127.0.0.1:8080/** (login: `mobsf` / `mobsf`).

See [mobsf/README.md](mobsf/README.md) and the MobSF doc set:

- [mobsf/INSTALL.md](mobsf/INSTALL.md) — first-time install
- [mobsf/OPERATIONS.md](mobsf/OPERATIONS.md) — day-to-day commands
- [mobsf/STACK.md](mobsf/STACK.md) — architecture and ports
- [mobsf/TROUBLESHOOTING.md](mobsf/TROUBLESHOOTING.md) — Fedora / SELinux fixes

### Optional: dev and web stack

```bash
sudo ./dev/git_setup.sh
sudo ./dev/install_vscode.sh
sudo ./dev/lamp_python_setup.sh
sudo ./dev/phpmyadmin_setup.sh
```

---

## Script index

### Launcher

| Script | Purpose | Sudo |
|--------|---------|------|
| `fedora.sh` | Lane picker → System, Dev, Android, MobSF | No |
| `fedora_rebuild.sh` | Guided full rebuild (separate; mode menu on start) | Maybe* |
| `system/system.sh` | System lane menu + CLI shortcuts | Maybe* |
| `dev/dev.sh` | Dev workstation lane menu + CLI shortcuts | Maybe* |
| `android/android.sh` | Android RE lane menu | Maybe* |
| `mobsf/mobsf.sh` | MobSF lane menu | Maybe* |

\*Some menu items invoke scripts that require sudo.

### System (`system/`)

| Script | Purpose | Sudo | Status |
|--------|---------|------|--------|
| `system_update.sh` | Full Fedora update, cleanup, kernel prune, RPM verify, health snapshot | Yes | **Keep** |
| `system_monitor.sh` | Live terminal dashboard (CPU, RAM, disk, network, RE process spotlight) | No | **Keep** |
| `system_info.sh` | One-shot system snapshot | No | **Keep** |
| `research_doctor.sh` | Android RE + MobSF readiness doctor | No | **Keep** |
| `view_logs.sh` | Deprecated shim → `log_engine.sh` (legacy flags in `lib/logging.sh`) | No | **Shim** |
| `backup_state.sh` | Export RPM list, configs, system info before reinstall | No | **Keep** |
| `cleanup.sh` | DNF cache clean, truncate logs, journal hints | Maybe | **Keep** |

### Developer workstation (`dev/`)

| Script | Purpose | Sudo | Status |
|--------|---------|------|--------|
| `git_setup.sh` | Git install + global identity and defaults | Maybe | **Keep** |
| `install_vscode.sh` | Microsoft VS Code repo + install | Yes | **Keep** |
| `fedora_container_kvm_setup.sh` | Podman, Docker, QEMU/KVM, libvirt, virt-manager | Maybe | **Keep** |
| `lamp_python_setup.sh` | Apache, MariaDB, PHP, Python MySQL connectors | Yes | **Keep** |
| `phpmyadmin_setup.sh` | phpMyAdmin + Apache/SELinux config | Yes | **Keep** |
| `web_stack_doctor.sh` | LAMP/phpMyAdmin HTTP and service checks | No | **Keep** |

### Android security research (`android/`)

| Script | Purpose | Sudo | Status |
|--------|---------|------|--------|
| `android_dev_core_setup.sh` | Core Android security workstation (Java, SDK, Frida, etc.) | Yes | **Keep** |
| `android_re_install.sh` | Install RE tools (apktool/jadx/smali/dex2jar/all) | No* | **Keep** |
| `android_re_apktool_user_install.sh` | Exec shim → `android_re_install.sh` | No* | **Shim** |
| `android_re_jadx_user_install.sh` | Exec shim → `android_re_install.sh` | No* | **Shim** |
| `android_re_smali_user_install.sh` | Exec shim → `android_re_install.sh` | No* | **Shim** |
| `android_re_dex2jar_user_install.sh` | Exec shim → `android_re_install.sh` | No* | **Shim** |
| `verify_re_tool.sh` | Verify one or all RE tools | No | **Keep** |
| `verify_apktool_install.sh` | Shim → verify_re_tool.sh | No | **Shim** |
| `verify_jadx_install.sh` | Shim → verify_re_tool.sh | No | **Shim** |
| `verify_smali_install.sh` | Shim → verify_re_tool.sh | No | **Shim** |
| `verify_dex2jar_install.sh` | Shim → verify_re_tool.sh | No | **Shim** |
| `verify_all_re_tools.sh` | Shim → verify_re_tool.sh all | No | **Shim** |
| `doctor_android_research.sh` | Full Android research readiness doctor | No | **Keep** |
| `helpers/debug_bash_env_verify_smali.sh` | Debug BASH_ENV issues with verify scripts | No | **Keep** |

\*May invoke `sudo dnf` for missing dependencies; installs land in `~/.local/`.

### MobSF (`mobsf/`)

| Script | Purpose | Sudo | Status |
|--------|---------|------|--------|
| `mobsf_install.sh` | First-time bootstrap (compose + podman + start) | Yes (`sudo -E`) | **Keep** |
| `mobsf_doctor.sh` | Readiness check (tools, compose, HTTP) | No | **Keep** |
| `mobsf_start.sh` / `mobsf_stop.sh` | Start/stop stack | Maybe | **Keep** |
| `mobsf_logs.sh` | Service logs | No | **Keep** |
| `mobsf_update.sh` | Pull images + migrate | Yes (`sudo -E`) | **Keep** |
| `mobsf_reset.sh` | Reset/rebuild stack (nuke or `--keep`) | Yes (`sudo -E`) | **Keep** |
| `compose/` | Fedora-patched docker-compose + nginx | — | **Keep** |
| `lib/` | MobSF shared library (paths, podman, stack, doctor) | — | **Keep** |

**Docs:** [mobsf/README.md](mobsf/README.md) · [INSTALL](mobsf/INSTALL.md) · [OPERATIONS](mobsf/OPERATIONS.md) · [STACK](mobsf/STACK.md) · [TROUBLESHOOTING](mobsf/TROUBLESHOOTING.md)

### Legacy (`legacy/`)

| Script | Purpose | Status |
|--------|---------|--------|
| `update_fedora.sh` | Minimal `dnf update` duplicate | **Deprecated** |
| `setup_dev_env.sh` | Old dev setup with system-wide pip | **Deprecated** |
| `FedoraInstallApps.sh` | yum-era bulk installer | **Archived** |
| `verify_smali_install.sh` | Duplicate of `android/verify_smali_install.sh` | **Deprecated** |

See [legacy/README.md](legacy/README.md) for replacements.

---

## Research workflow

This toolkit supports work on projects such as:

- ScytaleDroid, ObsidianDroid, Iapetus, Permission Intel
- MobSF static analysis
- Manual APK triage (apktool, jadx, smali, dex2jar)
- Dynamic Android analysis (Frida, Objection, mitmproxy, ADB)

Typical day-to-day ops:

```bash
./fedora.sh                      # menu entry point
./system/system_info.sh          # quick snapshot
./system/system_monitor.sh       # live dashboard
sudo ./system/system_update.sh   # maintained updates
./android/doctor_android_research.sh
```

---

## Conventions

- **Ops-grade scripts** use `set -euo pipefail`, structured logging, and idempotent re-runs.
- **Android RE installers** install to `~/.local/opt/` with wrappers in `~/.local/bin/` and managed PATH blocks in `~/.bashrc`.
- **Logging** — see [logs/README.md](logs/README.md). Engine in `lib/logging.sh`; CLI in `system/log_engine.sh`. Session banners, levels, archive/rotate.

### Logging quick reference

| Log file | Written by | How to view |
|----------|------------|-------------|
| `logs/system_update.log` | `system/system_update.sh` (always) | `./system/log_engine.sh summary` |
| `logs/fedora_rebuild.log` | `fedora_rebuild.sh --log` | `./system/log_engine.sh tail --file fedora_rebuild.log` |
| `logs/android_dev_core.log` | `android/android_dev_core_setup.sh` (always) | `./system/log_engine.sh tail --file android_dev_core.log` |
| `logs/mobsf.log` | mobsf install/reset/update | `./system/log_engine.sh issues --file mobsf.log` |
| `logs/backups/*` | `system/backup_state.sh` | `./system/log_engine.sh list` |

Env: `FEDORA_LOG_LEVEL` (DEBUG\|INFO\|WARN\|ERROR), `FEDORA_LOG_ROTATE_MB` (default **10** for system_update, 0=off elsewhere).

---

## Requirements

- Fedora (tested on Fedora 43+)
- `sudo` for system packages and services
- Network access for GitHub releases and DNF repos
- Java 21 for apktool, jadx, smali, dex2jar wrappers
