# Getting Started — Fedora Workstation Control Plane

Quick map for **neptune** and other Fedora research workstations. This repo is **not Mercury** (no database backup/DR). Clone: `git clone https://github.com/kevin-ch-day/fedora-linux-scripts.git`

---

## Entry points

| Script | Use when |
|--------|----------|
| **`./run.sh`** | **Main Fedora toolkit** — system maintenance, workstation areas, guided rebuild, health checks |
| **`./setup.sh`** | **Repo readiness** — executable check, `./validate.sh --quick`, optional smoke |
| **`./mobsf.sh`** | **MobSF stack only** — install/start/reset/**doctor** (separate from `./run.sh`) |
| **`./fedora.sh`** | **Compatibility** — wrapper for `./run.sh` (older docs/scripts) |
| **`./fedora_rebuild.sh`** | **Rebuild engine** — same as `./run.sh --rebuild` when invoked directly |

`./fedora.sh` remains as a compatibility wrapper for older docs and scripts.

| Goal | Command |
|------|---------|
| **Daily driver check** | `./run.sh --daily-driver-check` or `./system/system.sh daily-driver` |
| Btrfs / LUKS / VirtualBox readiness | `./system/system.sh btrfs-health` · `luks-readiness` · `virtualbox-readiness` |
| Package update noise | `./system/system.sh package-noise` |
| After `dnf upgrade` | `./system/system.sh post-update-check` |
| **All-in-one toolkit check** | `./run.sh --check` |
| Fix DNF repos then re-check | `./run.sh --check --fix-repos` (sudo) |
| Full check (+ doctor smoke) | `./run.sh --check --full` |
| System maintenance | `./system/system.sh` or `./run.sh --system` |
| Developer tools | `./dev/dev.sh --developer-tools` or `./run.sh --dev` |
| Desktop environments | `./dev/dev.sh --desktop-environments` |
| Virtualization & containers | `./dev/dev.sh --virtualization` |
| Web/database stack | `./dev/dev.sh --web-stack` |
| Android RE & MobSF | `./android/android.sh` or `./run.sh --android` |
| Fedora doctor | `./run.sh --doctor` |
| Host baseline (fresh install) | `./run.sh --baseline` |
| Rebuild readiness | `./run.sh --rebuild-check` |
| MobSF stack doctor | `./mobsf.sh --doctor` |
| Workstation readiness menu | `./run.sh --system` → `[1] Workstation readiness` |
| Logs CLI | `./system/log_engine.sh` or System menu `[7]` |
| Repo validation | `./validate.sh` |
| Dynamic smoke tests | `./smoke_test.sh` or `./validate.sh --smoke --quick` |

```text
./run.sh                 Main menu (Fedora Workstation Toolkit)
                              [1] System maintenance · [2] Developer tools
                              [3] Desktop environments · [4] Virtualization
                              [5] Web/database stack · [6] Android RE & MobSF

./run.sh --rebuild       Guided sequence (update → KVM → Android → RE tools → …)
./mobsf.sh                  MobSF stack (separate entry — own menu)
```

Shortcuts:

```bash
./run.sh                    # interactive main menu
./run.sh --check            # validate + smoke + rebuild readiness (start here)
./run.sh --check --fix-repos   # same, but fixes DNF .repo permissions first (sudo)
./run.sh --check --full     # includes full smoke + Fedora doctor
./run.sh --daily-driver-check  # read-only stabilization report (Neptune-style)
./run.sh --doctor           # Fedora doctor (repo · lanes · workstation health)
./run.sh --baseline         # host baseline report → logs/
./run.sh --rebuild-check    # pre-rebuild readiness
./run.sh --rebuild          # guided rebuild (preferred)
./run.sh --rebuild --yes    # rebuild without step prompts
./run.sh --system           # open System maintenance directly
./run.sh --dev              # open Developer tools directly
./run.sh --android          # open Android RE & MobSF directly
./mobsf.sh                     # MobSF menu
./mobsf.sh --doctor            # MobSF-only check
./mobsf.sh --doctor --dynamic  # static + dynamic analysis readiness
```

Set `NO_COLOR=1` or pass `--no-color` on `./run.sh` for plain terminal output.

---

## First time on a new machine

1. Clone this repo:
   ```bash
   git clone https://github.com/kevin-ch-day/fedora-linux-scripts.git
   cd fedora-linux-scripts
   ```
2. **Validate before major setup** (read-only; installs nothing):
   ```bash
   ./run.sh --check
   ```
   If rebuild readiness fails on **dnf repo permissions** (common on fresh installs):
   ```bash
   sudo ./run.sh --fix-repos
   ./run.sh --check
   ```
   Or in one step: `./run.sh --check --fix-repos`
   Or step-by-step:
   ```bash
   ./validate.sh --quick
   ./smoke_test.sh --quick
   ./run.sh --doctor
   ./run.sh --baseline
   ./run.sh --rebuild-check
   ```
   `--baseline` saves a timestamped host report under `logs/fresh_install_check_*.log`.
3. Run the full rebuild:
   ```bash
   ./run.sh --rebuild
   ```
   Pick a mode (interactive or auto-yes), confirm each major step. If a step fails, the rebuild continues and reports a failure count at the end.
4. Log out/in (or reboot) after desktop/KVM group changes; `source ~/.bashrc` for PATH.
5. Verify:
   ```bash
   ./run.sh --doctor
   ```
6. *(Optional)* MobSF static analysis stack:
   ```bash
   ./mobsf.sh install
   ./mobsf.sh --doctor
   ```

---

## Daily workflow

```bash
./run.sh --daily-driver-check   # quick read-only health (boot · btrfs · LUKS · vbox)
./run.sh          # main menu — exit a lane to return here
./run.sh 6        # jump straight into Android RE & MobSF (then exit to shell)
./mobsf.sh           # MobSF stack menu (separate from run.sh)
```

After `sudo ./system/system_update.sh`: run `./system/system.sh post-update-check` (the update script prints this and may offer to run it).

Recovery playbook (btrfs · LUKS · boot · VirtualBox): [RECOVERY.md](RECOVERY.md).

Readiness checks are **read-only by default**. Destructive actions (`--scrub`, `--stop-session`, hardening) require explicit flags or menu confirmation.

**Menu tips:** At any prompt, `[r]` repeats your last choice. `[0]` exits the lane picker or goes back one level in submenus. Menu reference: [AUDIT.md](AUDIT.md#menu-ux-reference).

**CLI shortcuts** (`./run.sh 1`–`6`, `--system`, `--dev`, `--android`, `--doctor`, `--baseline`, `--rebuild-check`, `--rebuild`) run the target script and **exit to your shell** — they do not return to the lane picker. Use `./run.sh` with no args for the interactive menu loop.

| Item | Key / launcher | Typical tasks |
|------|----------------|---------------|
| System maintenance | `1` / `./run.sh --system` | `dnf` update, logs, host snapshot |
| Developer tools | `2` / `./run.sh --dev` | git identity, VS Code, tool verification |
| Desktop environments | `3` / `./run.sh 3` | Cinnamon baseline, KDE, MATE, LXQt |
| Virtualization & containers | `4` / `./run.sh 4` | Podman, Docker, KVM, VirtualBox |
| Web/database stack | `5` / `./run.sh 5` | Apache, MariaDB, PHP, phpMyAdmin |
| Android RE & MobSF | `6` / `./run.sh --android` | SDK, RE tools, verify, ADB, MobSF |
| Guided rebuild | `7` / `./run.sh --rebuild` | full workstation setup |
| System health check | `8` / `./run.sh --doctor` | entry points · Android RE workstation |
| Toolkit self-test | `9` / `./run.sh --check` | validate, smoke, rebuild readiness |
| MobSF *(separate)* | `./mobsf.sh` · `./mobsf.sh --doctor` | stack install/start · MobSF health |

From inside a submenu opened via `./run.sh`, choose **[0] Back** to return to the previous menu.

Lane guides: [system/README.md](../system/README.md) · [dev/README.md](../dev/README.md) · [android/README.md](../android/README.md) · [mobsf/GUIDE.md](../mobsf/GUIDE.md)

---

## Doctor matrix (no double-runs)

| Script | Scope | When to use |
|--------|-------|-------------|
| `./run.sh --doctor` (`research_doctor.sh --android-only`) | Entry points · Android RE | Main menu `[5]`; daily verify |
| `research_doctor.sh` (full, no flags) | Android **+** MobSF | End of guided rebuild only |
| `android/doctor_android_research.sh` | Android only | Android RE & MobSF area; `--with-mobsf` for brief MobSF note |
| `./mobsf.sh --doctor` | MobSF stack only | Install/start/health for Podman stack |
| `dev/web_stack_doctor.sh` | LAMP / phpMyAdmin | After dev stack install |

**Do not run** Android doctor and `research_doctor.sh` back-to-back — rebuild ends with **research doctor only**.

---

## Logs

| Preferred | Deprecated |
|-----------|------------|
| `./system/log_engine.sh tail --file NAME --lines N` | `./system/view_logs.sh` (legacy flag shim) |

Log files: `system_update.log`, `fedora_rebuild.log`, `android_dev_core.log`, `mobsf.log` — see [logs/README.md](../logs/README.md).

---

## RE tools (preferred CLIs)

| Task | Command |
|------|---------|
| Install all | `./android/android_re_install.sh all` |
| Upgrade one | `./android/android_re_install.sh --upgrade jadx` |
| Verify all | `./android/verify_re_tool.sh all` |

Legacy shims (`android_re_*_user_install.sh`, `verify_*_install.sh`) still exec the preferred scripts above. Install logic: **`lib/android_re.sh`**.

---

## Rebuild sequence

1. System update  
2. Containers + KVM  
3. Android core  
4. RE tools install (`android_re_install.sh all`)  
5. Verify all RE tools  
6. *(optional)* MobSF install  
7. **Research doctor** (Android + MobSF)

Skip doctor: `./run.sh --rebuild --skip-doctor`

### After rebuild (optional — not in guided sequence)

Rebuild covers system update, KVM, Android core, RE tools, optional MobSF, and research doctor. Run these separately when needed:

| Task | Command |
|------|---------|
| Git identity | `./dev/git_setup.sh` |
| VS Code | `sudo ./dev/install_vscode.sh` |
| **Desktop environments** | `sudo ./dev/desktop_setup.sh` (`@cinnamon-desktop` + fallbacks) |
| KDE Plasma only | `sudo ./dev/desktop_setup.sh --only-profiles kde --default-session plasma` |
| VirtualBox host | `sudo ./dev/virtualbox_setup.sh` |
| LAMP / phpMyAdmin | `sudo ./dev/lamp_python_setup.sh` · `sudo ./dev/phpmyadmin_setup.sh` |

Desktop details: [dev/README.md](../dev/README.md#desktop-environments-cinnamon)

---

## Legacy folder

`legacy/` scripts are **disabled** (reference only). Use current lane scripts — see [legacy/README.md](../legacy/README.md).

---

## More detail

- [README.md](../README.md) — full script index
- [docs/README.md](README.md) — documentation index
- `./validate.sh` — quick repo health check before push
