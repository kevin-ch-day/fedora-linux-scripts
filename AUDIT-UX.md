# Fedora Toolkit — Menu UX Audit

**Repo:** `fedora-linux-scripts` (standalone; Kali sections below are historical from the former `Linux-Scripts` monorepo)

**Companion to:** [AUDIT-CODE.md](AUDIT-CODE.md) · [AUDIT.md](AUDIT.md)  
**Audit date:** 2026-06-07 (ongoing)  
**Scope:** Interactive menus, control flow, testing ergonomics

---

## Problem statement

During iterative testing, menus often felt like they “started over”:

- Script failures called `die` / `require_ok` and dropped the user to a shell
- Lane subprocess exit codes bubbled up through `set -e`
- No breadcrumb trail, repeat-last, or scroll mode for long output
- Rebuild wizards aborted entirely on the first failed step
- Duplicate doctor entries across lanes

---

## UX legend

| Symbol | Meaning |
|--------|---------|
| **pause** | `menu_pause` — press Enter to return to the same menu |
| **scroll** | Scroll mode — screen not cleared; output kept above |
| **sudo** | Runs with `sudo bash` |
| **sudo -E** | Runs with `sudo -E bash` (MobSF env preserved) |
| **confirm** | Extra in-menu confirmation before destructive action |
| **soft-fail** | Script error warns and stays in menu (no `die`) |
| **← last** | Menu item marked when it matches `[r]` repeat target |

### Global keys (all menus)

| Key | Action |
|-----|--------|
| `[0]` | Back one level (lane main → lane picker on Fedora) |
| `[r]` | Repeat last numeric choice |
| Ctrl+C on follow/tail | Returns when script exits (may skip pause on live follow) |

---

## Shared menu engine

| Feature | Fedora `lib/menu.sh` | Kali `lib/menu.sh` |
|---------|---------------------|-------------------|
| Version | 0.3.2 | 0.2.2 |
| Soft-fail runners | yes | yes |
| Soft-fail `menu_open_file` | yes | yes |
| Breadcrumbs (`MENU_STACK`) | yes | yes |
| Repeat last `[r]` | yes | yes |
| Scroll mode helpers | yes (+ sudo/env variants) | yes |
| `← last` on `menu_item` | yes | yes |
| Lane exit helper | `menu_item_lane_exit` | N/A (flat root) |

---

## Fedora — full menu tree

### Lane picker (`fedora.sh` v0.5.5)

```
Lane picker
├── [1] System lane      → exec system/system.sh
├── [2] Dev lane         → exec dev/dev.sh
├── [3] Android RE lane  → exec android/android.sh
├── [4] MobSF lane       → exec mobsf/mobsf.sh
├── [5] Guided rebuild   → fedora_rebuild.sh (FEDORA_FROM_MENU=1) · pause · soft-fail
└── [0] Exit
```

CLI shortcuts (leave menus — by design): `./fedora.sh 1`–`4`, `--doctor`, `--rebuild*`

---

### System lane (`system/lib/menu.sh` v0.2.1)

```
System menu
├── [1] Host visibility
│   ├── [1] System info snapshot                    pause
│   ├── [2] Live system monitor                     (Ctrl+C)
│   ├── [3] Post-update health snapshot             pause
│   ├── [4] Disk usage summary                      pause
│   └── [5] Top processes (CPU)                     pause
├── [2] Maintenance
│   ├── [1] Full Fedora update                      sudo · pause
│   ├── [2] Backup system state                     pause
│   ├── [3] Cleanup → submenu
│   │   ├── [1] Truncate system_update.log          pause · --quiet
│   │   ├── [2] Truncate all .log files             pause · --quiet
│   │   ├── [3] Archive system_update.log           pause · --quiet
│   │   ├── [4] Rotate system_update.log (10 MB)    pause · --quiet
│   │   └── [5] DNF clean                           sudo · pause
│   └── [4] Failed systemd units                    pause
├── [3] Logs (scroll on all log_engine actions)
│   ├── [1] Engine status                           scroll · pause
│   ├── [2] List logs + archives                    scroll · pause
│   ├── [3] Summary (system_update.log)             scroll · pause
│   ├── [4] Issues / errors                         scroll · pause
│   ├── [5] Tail system_update.log (50)             scroll · pause
│   ├── [6] Tail fedora_rebuild.log (50)            scroll · pause
│   ├── [7] Tail mobsf.log (50)                     scroll · pause
│   ├── [8] Follow system_update.log                scroll · (Ctrl+C)
│   └── [9] Open logs/README                        pause
├── [4] Research doctor (Android + MobSF)           scroll · pause
├── [5] Help & docs
│   ├── GETTING-STARTED · README · CONSOLIDATION · logs/README
└── [0] Back to lane picker
```

**Canonical full-stack doctor:** System lane `[4]` only.

---

### Dev lane (`dev/lib/menu.sh` v0.2.0)

```
Dev menu
├── [1] Workstation
│   ├── [1] Git setup (prompts)                     pause
│   ├── [2] Git config status                       scroll · pause · --status
│   ├── [3] Install VS Code                         sudo · pause
│   ├── [4] Desktop: Cinnamon + fallbacks           sudo · pause
│   └── [5] Desktop status                          pause
├── [2] Infrastructure
│   ├── [1] Containers + KVM                        sudo · pause
│   └── [2] Research service status                 pause
├── [3] Web stack
│   ├── [1] LAMP + Python (localhost)               sudo · pause
│   ├── [2] phpMyAdmin (localhost default)          sudo · pause
│   ├── [3] Web stack doctor                        scroll · pause
│   └── [4] Remove public info.php                  sudo · pause
├── [4] Help & docs
│   ├── GETTING-STARTED · README · dev/README
└── [0] Back to lane picker
```

Set `GIT_NAME` / `GIT_EMAIL` in the environment to skip git setup prompts.

---

### Android lane (`android/lib/menu.sh` v0.2.1)

```
Android menu
├── [1] Setup
│   └── [1] Install Android core tools              sudo · pause
├── [2] RE tool installs
│   ├── [1–4] apktool · jadx · smali · dex2jar      pause
│   ├── [5] Install all four                        pause
│   ├── [6] Install all + verify all                scroll on verify
│   └── [7–10] Per-tool install + verify            scroll on verify
├── [3] Verify (scroll)
│   ├── all · apktool · jadx · smali · dex2jar
│   └── debug smali env helper
├── [4] Doctors & ADB
│   ├── [1] Android research doctor (lane-scoped)   scroll · pause
│   └── [2] ADB devices / status                    pause
├── [5] Lane guide (README)
└── [0] Back to lane picker
```

**Note:** Full research doctor (Android + MobSF) is System lane `[4]`, not duplicated here.

---

### MobSF lane (`mobsf/lib/menu.sh`)

```
MobSF menu
├── [1] Stack control
│   ├── [1] Start stack                             sudo -E · pause
│   ├── [2] Stop stack                              pause
│   ├── [3] Container status                        pause
│   └── [4] Open web UI in browser                  pause
├── [2] Setup
│   ├── [1] Install / bootstrap                     sudo -E · pause
│   └── [2] Doctor — readiness check                scroll · pause
├── [3] Maintenance
│   ├── [1] Update images + migrate                 sudo -E · pause
│   ├── [2] Reset — nuke data                       confirm · sudo -E · pause
│   ├── [3] Reset — keep scan data                  confirm · sudo -E · pause
│   └── [4] Remove orphan containers                pause
├── [4] Logs (scroll)
│   ├── container logs (80 lines)
│   ├── tail / follow / issues on mobsf.log
├── [5] Documentation (README · INSTALL · …)
└── [0] Back to lane picker
```

---

### Guided rebuild (`fedora_rebuild.sh` v0.4.5)

Runs **outside** lane trees. From picker `[5]` returns to picker after completion.

| Behavior | Status |
|----------|--------|
| Step confirm (unless `--yes` / `--dry-run`) | yes |
| Skip MobSF/doctor prompts on `--dry-run` | yes |
| Skip mode picker when `FEDORA_FROM_MENU=1` | yes |
| **Soft-fail on step error** (continue + count failures) | yes (v0.4.5) |
| End summary when failures > 0 | yes |

Core steps: system update → dev stack → containers/KVM → Android core → RE install all → verify all → optional MobSF → optional research doctor.

---

## Kali — full menu tree

### Root menu (`kali.sh` v0.2.2)

```
Kali menu
├── [1] System & packages
│   ├── [1] System update                           sudo · pause
│   └── [2] Baseline lab packages                   sudo · pause
├── [2] Android lab
│   ├── [1] Android RE tools + venv                 sudo · pause
│   └── [2] Install + verify (RE doctor)            sudo then scroll · pause
├── [3] Doctors
│   ├── [1] Android RE doctor                       scroll · pause
│   ├── [2] MobSF doctor (native)                   scroll · pause
│   ├── [3] Full lab doctor                         scroll · pause
│   └── [4] Environment / VM doctor                 scroll · pause
├── [4] Web stack (phpMyAdmin)
│   ├── [1] phpMyAdmin install                      sudo · pause
│   └── [2] phpMyAdmin status                       scroll · pause
├── [5] MobSF (native)
│   ├── [1] MobSF doctor                            scroll · pause
│   └── [2] MobSF native install                    sudo · pause
├── [6] GitHub setup + checks (scroll on check/test items)
├── [7] Optional: Java / Chrome / Kotlin
├── [8] Guided rebuild                              KALI_FROM_MENU=1 · pause · soft-fail
├── [9] Help & docs                                 README · config.env.example
└── [0] Exit
```

**Doctor dedup:** Android RE doctor removed from Android lab submenu (v0.2.1); use Doctors `[1]`.

MobSF doctor appears in both Doctors `[2]` and MobSF `[1]` intentionally (quick access vs native install context).

### Guided rebuild (`kali_rebuild.sh` v0.1.3)

Same soft-fail pattern as Fedora: failed steps warn, rebuild continues, summary at end. Logging parity with Fedora (including dry-run + `--log`).

---

## Fixes applied (UX pass)

| Fix | Where |
|-----|-------|
| Menu soft-fail (no `die` on script error) | `lib/menu.sh` |
| Lane picker survives lane exit ≠ 0 | `fedora.sh` v0.5.2+ |
| Breadcrumbs + `[r]` repeat | Both menu libs |
| Scroll mode for logs/doctors | System, MobSF, Android verify, Dev web doctor |
| Help & docs submenu | System lane |
| Android per-tool install+verify | Android lane items 7–10 |
| Dedupe full research doctor | Android lane (points to System) |
| Dedupe Android RE doctor | Kali Android lab |
| MobSF nuke confirm | MobSF maintenance `[2]` |
| Rebuild soft-fail + failure summary | `fedora_rebuild.sh` v0.4.5, `kali_rebuild.sh` v0.1.2 |
| Picker rebuild item `[5]` | `fedora.sh` v0.5.5 |
| `← last` marker on menu items | Fedora v0.3.1, Kali v0.2.1 |
| Dev Help & docs + git `--status` | Dev lane v0.2.0, `git_setup.sh` v0.3.1 |
| Kali Help & docs + install+verify | `kali.sh` v0.2.2 |
| MobSF reset `--keep` confirm | MobSF maintenance |
| `menu_open_file` soft-fail | Fedora v0.3.2, Kali v0.2.2 |
| Host visibility scroll mode | System lane v0.2.2 |
| Kali rebuild logging parity | `kali_rebuild.sh` v0.1.3 |

---

## Known remaining gaps

| Item | Priority | Notes |
|------|----------|-------|
| CLI `exec` shortcuts never return to menus | by design | Document in GETTING-STARTED |
| MobSF doctor in two Kali submenus | low | Different contexts; acceptable |
| Per-tool install+verify outside Android/Kali android | low | Fedora Android has per-tool; Kali has combo |
| Compact headers / fewer redraws | enhancement | Scroll mode partially addresses |

---

## Testing ergonomics

Recommended loop for menu QA:

```bash
cd fedora-linux-scripts
./fedora.sh
# Pick lane → action → [r] to repeat last
# Force a failure (e.g. missing sudo) — should warn, stay in menu
./fedora_rebuild.sh --dry-run   # should not hang on MobSF/doctor confirms
```

Non-interactive lane shortcut `./fedora.sh 1` exits to shell (no TTY) — expected.

---

## See also

- [GETTING-STARTED.md](GETTING-STARTED.md) — daily workflow, `[r]`, rebuild `[5]`
- [AUDIT-CODE.md](AUDIT-CODE.md) — code-level findings and ShellCheck baseline
