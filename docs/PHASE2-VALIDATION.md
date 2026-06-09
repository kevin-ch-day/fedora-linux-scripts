# Phase 2 — Manual validation checklist (Neptune)

Repeatable operator pass after major system work or readiness changes. Run from the **repo root**:

```bash
cd ~/GitHub/fedora-linux-scripts   # adjust path if cloned elsewhere
```

**Scope:** read-only checks by default. No readiness history, diffing, or automatic LUKS/package changes in this pass.

**Time:** ~15–25 minutes interactive · ~5 minutes non-interactive only.

---

## Before you start

- [ ] Fedora 44+ host (Neptune or similar research workstation)
- [ ] Repo on disk with executable scripts (`chmod +x run.sh` if needed)
- [ ] Normal user session (not required to be root except where noted)
- [ ] Optional: `NO_COLOR=1` for plain output in logs

---

## Checklist

### 1. Main menu opens cleanly

```bash
./run.sh
```

- [ ] Banner and main menu render without errors
- [ ] Health line in header is compact (no full disk/memory dump)
- [ ] Choose `[0]` to exit — returns to shell cleanly

---

### 2. System menu shows Workstation readiness

```bash
./run.sh --system
```

- [ ] `[1] Workstation readiness` appears under **Workstation readiness**
- [ ] Submenu lists: Daily driver · Btrfs · LUKS · VirtualBox · Package noise · Post-update · Backup · Host context
- [ ] `[0]` back to system menu, then `[0]` exit to shell

---

### 3. Daily driver via run.sh

```bash
./run.sh --daily-driver-check
```

- [ ] Exits 0
- [ ] Reports OS, kernel, host model
- [ ] Includes boot (`systemd-analyze` if available), btrfs stats, failed units, RAM/swap, key mounts
- [ ] Includes LUKS keyslot hint, VirtualBox, package noise, kernel cmdline

---

### 4. Daily driver via system.sh

```bash
./system/system.sh daily-driver
```

- [ ] Same report as step 3
- [ ] Exits 0

---

### 5. Btrfs health (read-only)

```bash
./system/system.sh btrfs-health
```

- [ ] Does **not** start a scrub
- [ ] Shows `btrfs device stats /` (or notes if root is not btrfs)
- [ ] Shows scrub status if available
- [ ] On Neptune: expect `corruption_errs 0` when healthy

**Do not run** `--scrub` in this validation pass unless you intend a long-running scrub.

---

### 6. LUKS readiness (read-only)

```bash
./system/system.sh luks-readiness
# keyslot count requires luksDump — use sudo for full read:
sudo ./system/system.sh luks-readiness
```

- [ ] Detects LUKS block device (e.g. `/dev/sda3`) and mapper path
- [ ] Reports **keyslot count** with sudo (Neptune target: **2** keyslots, e.g. slots 0 and 1)
- [ ] Reports header backup under `$HOME/luks_backups/` and `/data/system_backups/neptune_luks/` (or `<host>_luks`)
- [ ] Reports kernel cmdline / `rhgb quiet` visibility
- [ ] Exits 0 when backup paths are present

---

### 7. LUKS add-passphrase flow (guarded — cancel before changes)

**Purpose:** confirm the interactive guardrails only. **Do not add a keyslot** unless you explicitly want to.

```bash
sudo ./system/system.sh luks-readiness --add-passphrase
```

Walk through until the first **write** confirmation, then **cancel**:

- [ ] Fails immediately if stdin is not a TTY (e.g. piped input)
- [ ] Requires `sudo` (root)
- [ ] Shows read-only LUKS summary first
- [ ] Confirms header backup exists (or warns and requires override)
- [ ] Shows **Keyslots (before)** — expect **2** on Neptune
- [ ] Prompts before reading passphrases (nothing echoed)
- [ ] At **“Write new passphrase to a new LUKS keyslot now? [y/N]”** → answer **`N`** (or cancel earlier)
- [ ] Exits without changing keyslot count
- [ ] Re-run step 6 — keyslot count still **2**

**Optional (only if you intend to add a slot):** answer `y` at the final prompt, complete the flow, verify **Keyslots (after)** increments by 1, and test new passphrase when offered.

---

### 8. VirtualBox readiness

```bash
./system/system.sh virtualbox-readiness
```

- [ ] Shows running kernel vs latest installed RPM kernel
- [ ] Shows `lsmod | grep vbox` (expect `vboxdrv`, `vboxnetflt`, `vboxnetadp` when healthy)
- [ ] Shows `vboxdrv` service state
- [ ] Shows `VBoxManage --version` when installed
- [ ] Exits 0 when modules and VBoxManage are ready (exit 1 acceptable if VB not installed — note in log)

---

### 9. Package noise

```bash
./system/system.sh package-noise
```

- [ ] Lists PackageKit / dnf / flatpak helpers **only if running**
- [ ] On a quiet Neptune: **no matching background processes** (or only expected brief activity)
- [ ] Does **not** remove packages

**Do not run** `--stop-session` in this pass unless you are deliberately clearing background updaters.

---

### 10. Post-update check

```bash
./system/system.sh post-update-check
```

- [ ] Runs reboot hint (`needs-restarting` if available)
- [ ] Checks btrfs stats, failed services, VirtualBox, package noise
- [ ] Prints summary box
- [ ] Exits 0 on stable system (exit 1 if issues found — document which)

**Optional:** after a real update:

```bash
sudo ./system/system_update.sh --quick
```

- [ ] Final output includes `Run  ./system/system.sh post-update-check`
- [ ] Prompt `Run post-update readiness check now? [y/N]` appears on interactive TTY
- [ ] Answer `N` to skip auto-run (or `y` to run step 10 inline)

---

### 11. validate.sh

```bash
./validate.sh --quick
```

- [ ] **Result: passed** · Issues: 0

---

### 12. smoke_test.sh

```bash
./smoke_test.sh --quick
```

- [ ] **Result: PASSED**
- [ ] Workstation readiness section includes daily driver, luks-readiness, post-update-check
- [ ] Health snapshot section completes without long hang (~20s total acceptable on Neptune)

---

## Sign-off

| Field | Value |
|-------|--------|
| Host | neptune |
| Date | 2026-06-09 |
| Kernel | 7.0.11-200.fc44.x86_64 |
| Validator | linuxadmin |
| Daily driver | **pass** |
| LUKS keyslots | **2** (with `sudo ./system/system.sh luks-readiness`) |
| Btrfs corruption_errs | **0** |
| VirtualBox | **pass** (vboxdrv · 7.2.8) |
| validate + smoke | **pass** |
| Notes | initrd ~64s (LUKS); userspace ~16s; Phase 2 polish: model via hostnamectl, LUKS by-uuid path, btrfs scrub sudo hint, smoke quick skips doctor |

### Neptune observations (informational)

- Boot: **1m 37s** total — **initrd 1m 4s** dominates (LUKS); userspace **15.6s** is healthy.
- `dnf-makecache.service` in `systemd-analyze blame` is userspace, not initrd delay.
- **nouveau: 23** kernel messages this boot — note only unless GPU issues appear.
- Header backups present at `$HOME/luks_backups/` and `/data/system_backups/neptune_luks/`.
- Run **#7** (add-passphrase cancel test) separately when ready.

---

## What this pass does **not** cover (Phase 3+)

- Readiness history or snapshot diffing
- State database / export store
- Main menu restructuring
- Automatic LUKS or package changes
- NVIDIA driver work
- MobSF stack (separate: `./mobsf.sh --doctor`)

---

## Related docs

- [RECOVERY.md](RECOVERY.md) — Neptune recovery playbook
- [GETTING-STARTED.md](GETTING-STARTED.md) — daily workflow
- [system/README.md](../system/README.md) — readiness commands
