# Getting Started — Fedora Workstation Control Plane

Quick map for **neptune** and other Fedora research workstations. This repo is **not Mercury** (no database backup/DR). Clone: `git clone https://github.com/kevin-ch-day/fedora-linux-scripts.git`

---

## Entry points

| Script | Use when |
|--------|----------|
| **`./run.sh`** | **Start here** — main menu, updates, install hub, guided rebuild, doctor |
| **`./inspect.sh`** | Detailed no-sudo host inventory; saves nothing unless `--save` is used |
| **`./setup.sh`** | **First clone** — executable check, `./validate.sh --quick`, optional smoke |
| **`./install.sh`** | **Install profiles** — one-command stacks (`research`, `android-re`, `mobsf`, …) |
| **`./mobsf.sh`** | **MobSF stack only** — install/start/reset/**doctor** (separate lifecycle) |

`./fedora.sh` and `./fedora_rebuild.sh` are legacy names that redirect to `./run.sh` (old bookmarks still work).

| Goal | Command |
|------|---------|
| **Daily driver check** | `./run.sh --daily-driver-check` or `./system/system.sh daily-driver` |
| Disk/memory summary | `./run.sh --disk-summary` or `./system/health_snapshot.sh --show` |
| Btrfs / LUKS / VirtualBox readiness | `./system/system.sh btrfs-health` · `luks-readiness` · `virtualbox-readiness` |
| Package update noise | `./system/system.sh package-noise` |
| **Update Fedora** | `./run.sh --update` or main menu **[1]** |
| **Daily sync (update + verify)** | `./run.sh --daily` or main menu **[2]** |
| After `dnf upgrade` only | `./run.sh --post-update-check` or main menu **[3]** |
| **All-in-one toolkit check** | `./run.sh --check` |
| Fix DNF repos then re-check | `./run.sh --check --fix-repos` (sudo) |
| Full check (+ doctor smoke) | `./run.sh --check --full` |
| System maintenance | `./system/system.sh` or `./run.sh --system` |
| Developer tools | `./dev/dev.sh --developer-tools` or `./run.sh --dev` |
| Desktop environments | `./dev/dev.sh --desktop-environments` |
| Virtualization & containers | `./dev/dev.sh --virtualization` |
| Web/database stack | `./dev/dev.sh --web-stack` |
| Android RE tools | `./android/android.sh` or `./run.sh --android` |
| Fedora doctor | `./run.sh --doctor` |
| Fresh install report | `./run.sh --baseline` |
| Rebuild readiness | `./run.sh --rebuild-check` |
| MobSF stack doctor | `./mobsf.sh --doctor` |
| Install workstation | `./run.sh --install` or main menu **[5]** |
| Install profiles | `./install.sh list` · `./install.sh workstation --yes` · [INSTALL-PROFILES.md](INSTALL-PROFILES.md) |
| Fresh machine wizard | `./run.sh --onboard` · `./setup.sh --guided` |
| System readiness menu | `./run.sh --system` → **[1] Update** · **[2] Daily sync** |
| Logs CLI | `./system/log_engine.sh` or System maintenance → **[9] View logs** |
| Repo validation | `./validate.sh` |
| Dynamic smoke tests | `./smoke_test.sh` or `./validate.sh --smoke --quick` |

```text
./run.sh                 Main menu (Fedora Workstation Toolkit)
                              [1] Update Fedora
                              [2] Update + post-update check  ← daily workflow
                              [3] Post-update check only
                              [4] Guided rebuild
                              [5] Install workstation hub
                              [6] System maintenance · [7] Doctor · [8] Self-test

./run.sh --daily         Update then post-update check (recommended)
./run.sh --install       Install hub (profiles [6–8] · dev · Android · rebuild)
./run.sh --list-profiles Profile catalog
./run.sh --workstation   Daily dev profile (update + VS Code + KVM)
./install.sh list        Profile catalog (research · android-re · dev-stack · …)
./run.sh --onboard       Fresh machine wizard (setup → check → rebuild)
./run.sh --rebuild       Guided sequence (research profile)
./mobsf.sh               MobSF stack (separate entry — own menu)
```

Shortcuts:

```bash
./run.sh                    # interactive main menu — [1] Update Fedora first
./run.sh --update           # full Fedora update (sudo)
./run.sh --daily            # update + post-update check (recommended)
./run.sh --daily --quick    # faster daily sync
./run.sh --install          # install workstation hub
./run.sh --onboard          # fresh machine: setup → check → rebuild
./install.sh list           # profile catalog
./install.sh research --yes # full research workstation (non-interactive)
./run.sh --check            # validate + smoke + rebuild readiness (start here)
./run.sh --check --fix-repos   # same, but fixes DNF .repo permissions first (sudo)
./run.sh --check --full     # includes full smoke + Fedora doctor
./run.sh --daily-driver-check
./run.sh --disk-summary        # disk/memory snapshot (auto-refresh if stale)
./run.sh --post-update-check   # after dnf upgrade
./run.sh --doctor           # Fedora doctor (repo · lanes · workstation health)
./run.sh --baseline         # host baseline report → logs/
./run.sh --rebuild-check    # pre-rebuild readiness
./run.sh --rebuild          # guided rebuild (preferred)
./run.sh --rebuild --yes    # rebuild without step prompts
./run.sh --system           # open System maintenance directly
./run.sh --dev              # open Developer tools directly
./run.sh --android          # open Android RE tools directly
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
   ./setup.sh
   # or guided path:
   ./setup.sh --guided
   # or full wizard:
   ./run.sh --onboard
   ```
   Manual check:
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
   # or non-interactive:
   ./install.sh research --yes
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
./run.sh --daily-driver-check
./run.sh --disk-summary        # disk/memory snapshot (auto-refresh if stale)
./run.sh --post-update-check   # after dnf upgrade
./run.sh          # main menu — exit a lane to return here
./run.sh 6        # jump straight into Android RE tools (then exit to shell)
./mobsf.sh           # MobSF stack menu (separate from run.sh)
```

After `sudo ./system/system_update.sh`: run `./run.sh --post-update-check` (the update script prints this and may offer to run it).

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
| Android RE tools | `6` / `./run.sh --android` | SDK, RE tools, verify, ADB (MobSF: `./mobsf.sh`) |
| Guided rebuild | `7` / `./run.sh --rebuild` | full workstation setup |
| System health check | `8` / `./run.sh --doctor` | entry points · Android RE workstation |
| Toolkit self-test | `9` / `./run.sh --check` | validate, smoke, rebuild readiness |
| MobSF *(separate)* | `./mobsf.sh` · `./mobsf.sh --doctor` | stack install/start · MobSF health |

From inside a submenu opened via `./run.sh`, choose **[0] Back** to return to the previous menu.

Lane guides: [system/README.md](../system/README.md) · [dev/README.md](../dev/README.md) · [android/README.md](../android/README.md) · [mobsf/GUIDE.md](../mobsf/GUIDE.md)

---

## Android verification tiers

Choose a core shape before installing:

```bash
./android/android.sh plan minimal    # headless/device host
./android/android.sh plan standard   # recommended RE workstation
./android/android.sh plan full       # + optional Node/npm and apk-mitm
```

The Android landing menu runs common installs directly. Per-tool installs,
upgrades, custom plans, and optional Node repair are grouped under one
**Advanced tools and plans** page. See
[android/README.md](../android/README.md) for component overrides and custom
SDK locations.

| Tier | Command | Scope |
|------|---------|--------|
| Core tools | `./android/android_dev_core_setup.sh --status` | adb, java, sdkmanager, frida, objection, mitmproxy (read-only) |
| APK RE tools | `./android/verify_all_re_tools.sh` | apktool, jadx, smali, dex2jar |
| Full doctor | `./android/doctor_android_research.sh` | Core + ADB + all RE tools |
| MobSF stack | `./mobsf.sh` · `./mobsf.sh --doctor` | Separate Podman lifecycle |

---

## Doctor matrix (no double-runs)

| Script | Scope | When to use |
|--------|-------|-------------|
| `./run.sh --doctor` (`research_doctor.sh --android-only`) | Entry points · Android RE | Main menu `[5]`; daily verify |
| `research_doctor.sh` (full, no flags) | Android **+** MobSF | End of guided rebuild only |
| `android/doctor_android_research.sh` | Android only | Android RE tools area; `--with-mobsf` for brief MobSF note |
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
