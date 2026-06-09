# Recovery Playbook — Fedora Workstation

Operator-facing recovery notes from **neptune** (Fedora 44 research workstation). Fedora-only. This repo is **not Mercury** (no database backup/DR manifests).

**Readiness commands:** `./fedora.sh --daily-driver-check` · `./system/system.sh btrfs-health` · `luks-readiness` · `post-update-check`

---

## Btrfs checksum corruption triage

### What `btrfs device stats /` means

```bash
btrfs device stats /
```

Each line is a counter for the root filesystem device. Focus on **`corruption_errs`**:

| Value | Meaning |
|-------|---------|
| `0` | No btrfs-reported checksum mismatches on read |
| `> 0` | At least one block failed checksum verification |

Also watch `read_io_errs`, `write_io_errs`, `generation_errs` — non-zero values deserve investigation.

**Healthy Neptune target:** `corruption_errs 0` after cleanup and scrub.

### Safe scrub usage

```bash
./system/system.sh btrfs-health          # read-only stats + last scrub status
./system/system.sh btrfs-health --scrub  # starts scrub on / (confirm · sudo)
```

- Scrub **reads every block** — can take hours on large drives.
- Run when the system is idle; monitor with `btrfs scrub status /`.
- A scrub finding errors points to **paths** in logs — not an automatic repair.

### Why not `btrfs check --repair`

**Do not run `btrfs check --repair`** unless you are following explicit upstream recovery guidance with backups. Repair mode can make damage worse on a live root filesystem. This toolkit never runs repair automatically.

Preferred order:

1. `btrfs device stats /` — confirm `corruption_errs`
2. Identify and remove/replace **replaceable** bad files (caches, SDK sources, app state DBs)
3. Scrub (`--scrub` with confirmation)
4. Re-check stats and scrub status

### Resolving bad paths from scrub logs

When scrub reports errors, note the **file paths** (if listed) or correlate with apps that were slow or crashing.

**Replaceable paths seen on Neptune** (safe to delete after quitting the app; they rebuild on next launch):

| Area | Typical path |
|------|----------------|
| Android SDK sources | Under `~/Android/Sdk/` or `~/.local/share/...` — re-fetch via SDK manager |
| Cursor global state | `~/.config/Cursor/User/globalStorage/state.vscdb` (and `-wal`/`-shm`) |
| VS Code WebStorage | `~/.config/Code/User/workspaceStorage/*/.../WebStorage/` |
| Chromium cache | `~/.cache/chromium/` or app-specific `Cache` / `CacheStorage` under `~/.config/` |

After removing suspect files:

```bash
./system/system.sh btrfs-health --scrub   # optional · confirm
./system/system.sh btrfs-health           # verify corruption_errs 0
```

---

## LUKS boot delay triage

### Slow boot vs LUKS unlock waiting

| Symptom | Likely cause |
|---------|----------------|
| Long pause **before** Plymouth/login, disk LED active | **initrd LUKS unlock** — passphrase retries, wrong keyboard layout, or hidden prompt |
| Slow **after** login, apps sluggish | Userspace — btrfs, services, IDE caches (not always RAM pressure) |

On Neptune, most boot delay was **LUKS passphrase retries in initrd**, not Fedora userspace startup.

Check userspace boot time only after unlock:

```bash
systemd-analyze
systemd-analyze blame | head -10
```

### Why `rhgb quiet` hides useful prompts

Kernel cmdline flags **`rhgb`** (RH graphical boot) and **`quiet`** suppress boot messages. On LUKS systems that can hide the passphrase prompt or retry feedback.

Check:

```bash
cat /proc/cmdline
./system/system.sh luks-readiness
```

Neptune fix: remove `rhgb quiet` so LUKS prompts and retries are visible. Adjust via `grubby`, `/etc/default/grub`, or kernel args — then regenerate grub config and reboot.

### LUKS header backup locations

Expected on research hosts:

```text
$HOME/luks_backups/
/data/system_backups/<hostname>_luks/    # e.g. neptune_luks
```

Verify:

```bash
./system/system.sh luks-readiness
```

Manual backup (run once, store copies in both locations):

```bash
sudo cryptsetup luksHeaderBackup /dev/sdX \
  --header-backup-file "$HOME/luks_backups/$(hostname)_luks_header_$(date +%Y%m%d).img"
```

Never commit header images or passphrases to git.

### Adding a backup LUKS passphrase

Prefer the toolkit flow (interactive · sudo · never prints passphrases):

```bash
sudo ./system/luks_readiness.sh --add-passphrase
# or
sudo ./system/system.sh luks-readiness --add-passphrase
```

Requirements enforced by the script:

- Header backup present (or explicit override after warning)
- Confirmation at each step
- Current passphrase tested optionally
- New passphrase entered twice
- Keyslot count shown before and after
- Optional test of new passphrase
- **No keyslots removed**

Manual equivalent (Neptune pattern — use key files, not argv passphrases):

```bash
OLDKEY_FILE="$(mktemp)" NEWKEY_FILE="$(mktemp)"
chmod 600 "$OLDKEY_FILE" "$NEWKEY_FILE"
# populate files interactively — never echo passphrases
cryptsetup open --test-passphrase --key-file "$OLDKEY_FILE" "$DEV"
cryptsetup luksAddKey "$DEV" "$NEWKEY_FILE" --key-file "$OLDKEY_FILE"
shred -u "$OLDKEY_FILE" "$NEWKEY_FILE"
```

---

## VirtualBox kernel mismatch

### Symptoms

- `vboxdrv` failed / not loaded
- `VBoxManage` present but VMs won't start
- `systemctl status vboxdrv` inactive after a kernel update

### Check

```bash
./system/system.sh virtualbox-readiness
```

Common cause: **booted an older kernel** while `kernel-devel` / `akmod-VirtualBox` built for the newest.

Fix:

1. Reboot into the latest kernel (`uname -r` matches newest `rpm -q kernel`)
2. `sudo ./dev/virtualbox_setup.sh` if modules still missing
3. Confirm: `lsmod | grep vbox`, `vboxmanage --version`

---

## Package / update helper noise

Background processes can make the system feel busy or block `dnf`:

- `PackageKit`
- `dnfdragora`
- `dnf5daemon`
- `rpm`
- `flatpak` helpers

Check:

```bash
./system/system.sh package-noise
```

Stop for **current session only** (no package removal):

```bash
./system/system.sh package-noise --stop-session
```

After `sudo ./system/system_update.sh`, run:

```bash
./system/system.sh post-update-check
```

The update script prints this next step and may offer to run it interactively.

---

## Quick recovery checklist

```bash
./fedora.sh --daily-driver-check
./system/system.sh btrfs-health
./system/system.sh luks-readiness
./system/system.sh virtualbox-readiness
./system/system.sh package-noise
./system/system.sh post-update-check    # after dnf upgrade
```

More: [GETTING-STARTED.md](GETTING-STARTED.md) · [system/README.md](../system/README.md)
