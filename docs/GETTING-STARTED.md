# Getting Started — Fedora Rebuild Kit

Quick map for **neptune** and other Fedora research workstations. Clone: `git clone https://github.com/kevin-ch-day/fedora-linux-scripts.git`

---

## Entry points

| Script | Use when |
|--------|----------|
| **`./fedora.sh`** | **Main Fedora toolkit** — System, Development, Android RE; guided rebuild; Fedora doctor |
| **`./mobsf.sh`** | **MobSF stack only** — install/start/reset/**doctor** (separate from `./fedora.sh`) |
| **`./fedora_rebuild.sh`** | **Compatibility** — same as `./fedora.sh --rebuild` |

| Goal | Command |
|------|---------|
| **All-in-one readiness** | `./fedora.sh --check` |
| Fix DNF repos then re-check | `./fedora.sh --check --fix-repos` (sudo) |
| Full check (+ doctor smoke) | `./fedora.sh --check --full` |
| System lane | `./system/system.sh` or `./fedora.sh --system` |
| Development lane | `./dev/dev.sh` or `./fedora.sh --dev` |
| Android lane | `./android/android.sh` or `./fedora.sh --android` |
| Fedora doctor | `./fedora.sh --doctor` |
| Host baseline (fresh install) | `./fedora.sh --baseline` |
| Rebuild readiness | `./fedora.sh --rebuild-check` |
| MobSF stack doctor | `./mobsf.sh --doctor` |
| Logs CLI | `./system/log_engine.sh` or System menu `[5]` |
| Repo validation | `./validate.sh` |
| Dynamic smoke tests | `./smoke_test.sh` or `./validate.sh --smoke --quick` |

```text
./fedora.sh                 Main menu (Fedora Workstation Toolkit)
                              [1] System · [2] Development · [3] Android RE
                              [4] Guided rebuild · [5] Fedora doctor
                              MobSF: ./mobsf.sh (separate)

./fedora.sh --rebuild       Guided sequence (update → KVM → Android → RE tools → …)
./mobsf.sh                  MobSF stack (separate entry — own menu)
```

Shortcuts:

```bash
./fedora.sh                    # interactive main menu
./fedora.sh --check            # validate + smoke + rebuild readiness (start here)
./fedora.sh --check --fix-repos   # same, but fixes DNF .repo permissions first (sudo)
./fedora.sh --check --full     # includes full smoke + Fedora doctor
./fedora.sh --doctor           # Fedora doctor (repo · lanes · workstation health)
./fedora.sh --baseline         # host baseline report → logs/
./fedora.sh --rebuild-check    # pre-rebuild readiness
./fedora.sh --rebuild          # guided rebuild (preferred)
./fedora.sh --rebuild --yes    # rebuild without step prompts
./fedora.sh --system           # open System lane directly
./fedora.sh --dev              # open Development lane directly
./fedora.sh --android          # open Android RE lane directly
./mobsf.sh                     # MobSF menu
./mobsf.sh --doctor            # MobSF-only check
./mobsf.sh --doctor --dynamic  # static + dynamic analysis readiness
```

Set `NO_COLOR=1` or pass `--no-color` on `./fedora.sh` for plain terminal output.

---

## First time on a new machine

1. Clone this repo:
   ```bash
   git clone https://github.com/kevin-ch-day/fedora-linux-scripts.git
   cd fedora-linux-scripts
   ```
2. **Validate before major setup** (read-only; installs nothing):
   ```bash
   ./fedora.sh --check
   ```
   If rebuild readiness fails on **dnf repo permissions** (common on fresh installs):
   ```bash
   sudo ./fedora.sh --fix-repos
   ./fedora.sh --check
   ```
   Or in one step: `./fedora.sh --check --fix-repos`
   Or step-by-step:
   ```bash
   ./validate.sh --quick
   ./smoke_test.sh --quick
   ./fedora.sh --doctor
   ./fedora.sh --baseline
   ./fedora.sh --rebuild-check
   ```
   `--baseline` saves a timestamped host report under `logs/fresh_install_check_*.log`.
3. Run the full rebuild:
   ```bash
   ./fedora.sh --rebuild
   ```
   Pick a mode (interactive or auto-yes), confirm each major step. If a step fails, the rebuild continues and reports a failure count at the end.
4. Log out/in (or reboot) after desktop/KVM group changes; `source ~/.bashrc` for PATH.
5. Verify:
   ```bash
   ./fedora.sh --doctor
   ```
6. *(Optional)* MobSF static analysis stack:
   ```bash
   ./mobsf.sh install
   ./mobsf.sh --doctor
   ```

---

## Daily workflow

```bash
./fedora.sh          # main menu — exit a lane to return here
./fedora.sh 3        # jump straight into Android lane (then exit to shell)
./mobsf.sh           # MobSF stack menu (separate from fedora.sh)
```

**Menu tips:** At any prompt, `[r]` repeats your last choice. `[0]` exits the lane picker or goes back one level in submenus. Menu reference: [AUDIT.md](AUDIT.md#menu-ux-reference).

**CLI shortcuts** (`./fedora.sh 1`–`3`, `--system`, `--dev`, `--android`, `--doctor`, `--baseline`, `--rebuild-check`, `--rebuild`) run the target script and **exit to your shell** — they do not return to the lane picker. Use `./fedora.sh` with no args for the interactive menu loop.

| Item | Key / launcher | Typical tasks |
|------|----------------|---------------|
| System | `1` / `./fedora.sh --system` | `dnf` update, logs, host snapshot |
| Dev | `2` / `./fedora.sh --dev` | git, VS Code, Cinnamon desktop, KVM, LAMP |
| Android | `3` / `./fedora.sh --android` | SDK, RE tools, verify, ADB |
| Rebuild | `4` / `./fedora.sh --rebuild` | full workstation setup |
| Fedora doctor | `5` / `./fedora.sh --doctor` | entry points · Android RE workstation |
| MobSF *(separate)* | `./mobsf.sh` · `./mobsf.sh --doctor` | stack install/start · MobSF health |

From inside a lane opened via `./fedora.sh`, choose **[0] Back to lane picker** to switch lanes without restarting.

Lane guides: [system/README.md](../system/README.md) · [dev/README.md](../dev/README.md) · [android/README.md](../android/README.md) · [mobsf/GUIDE.md](../mobsf/GUIDE.md)

---

## Doctor matrix (no double-runs)

| Script | Scope | When to use |
|--------|-------|-------------|
| `./fedora.sh --doctor` (`research_doctor.sh --android-only`) | Entry points · Android RE | Main menu `[5]`; daily verify |
| `research_doctor.sh` (full, no flags) | Android **+** MobSF | End of guided rebuild only |
| `android/doctor_android_research.sh` | Android only | Android lane; `--with-mobsf` for brief MobSF note |
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

Skip doctor: `./fedora.sh --rebuild --skip-doctor`

### After rebuild (optional — not in guided sequence)

Rebuild covers system update, KVM, Android core, RE tools, optional MobSF, and research doctor. Run these separately when needed:

| Task | Command |
|------|---------|
| Git identity | `./dev/git_setup.sh` |
| VS Code | `sudo ./dev/install_vscode.sh` |
| **Cinnamon desktop** | `sudo ./dev/desktop_setup.sh` (`@cinnamon-desktop` + fallbacks) |
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
