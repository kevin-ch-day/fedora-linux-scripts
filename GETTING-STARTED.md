# Getting Started — Fedora Rebuild Kit

Quick map for **neptune** and other Fedora research workstations. Clone: `git clone https://github.com/kevin-ch-day/fedora-linux-scripts.git`

---

## Two entry points (do not confuse them)

| Script | Use when |
|--------|----------|
| **`./fedora.sh`** | **Daily work** — open System, Dev, Android, or MobSF lane menu |
| **`./fedora_rebuild.sh`** | **Full setup** — after fresh install or major upgrade (run rarely) |

```text
./fedora.sh                 Lane picker → execs one of:
                              ./system/system.sh
                              ./dev/dev.sh
                              ./android/android.sh
                              ./mobsf/mobsf.sh

./fedora_rebuild.sh         Guided sequence (update → KVM → Android → RE tools → …)
```

Shortcuts:

```bash
./fedora.sh --doctor           # Android + MobSF readiness
./fedora.sh --rebuild          # same as ./fedora_rebuild.sh
./fedora_rebuild.sh --yes      # rebuild without mode menu / step prompts
```

---

## First time on a new machine

1. Clone this repo:
   ```bash
   git clone https://github.com/kevin-ch-day/fedora-linux-scripts.git
   cd fedora-linux-scripts
   ```
2. Run the full rebuild:
   ```bash
   ./fedora_rebuild.sh
   ```
   Pick a mode (interactive or auto-yes), confirm each major step. If a step fails, the rebuild continues and reports a failure count at the end.
3. Log out/in or `source ~/.bashrc` for PATH and group changes.
4. Verify:
   ```bash
   ./fedora.sh --doctor
   ```

---

## Daily workflow

```bash
./fedora.sh          # lane picker — exit a lane to return here
./fedora.sh 3        # jump straight into Android lane (then exit to shell)
```

**Menu tips:** At any prompt, `[r]` repeats your last choice (handy for verify loops). `[0] Back` goes up one level. See [AUDIT-UX.md](AUDIT-UX.md) for the full menu map.

| Lane | Key / launcher | Typical tasks |
|------|----------------|---------------|
| System | `1` / `./system/system.sh` | `dnf` update, logs, host snapshot, research doctor |
| Dev | `2` / `./dev/dev.sh` | git, VS Code, KVM, LAMP |
| Android | `3` / `./android/android.sh` | SDK, RE tools, verify, ADB |
| MobSF | `4` / `./mobsf/mobsf.sh` | install/start stack, static APK analysis |
| Rebuild | `5` / `./fedora_rebuild.sh` | full workstation setup (leaves lane menus) |

From inside a lane opened via `./fedora.sh`, choose **[0] Back to lane picker** to switch lanes without restarting.

Lane guides: [system/README.md](system/README.md) · [dev/README.md](dev/README.md) · [android/README.md](android/README.md) · [mobsf/README.md](mobsf/README.md)

---

## Legacy folder

`legacy/` scripts are **disabled** (reference only). Use current lane scripts — see [legacy/README.md](legacy/README.md).

---

## More detail

- [README.md](README.md) — full script index
- [CONSOLIDATION.md](CONSOLIDATION.md) — doctors, logs, merge map
