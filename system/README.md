# System maintenance lane

Host maintenance, workstation readiness, updates, logs, and cleanup for Fedora research workstations.

**Menu:** `./system/system.sh` · **From main entry:** `./run.sh` → `[1]` or `./run.sh --system`

---

## Workstation readiness (read-only by default)

| Check | Command |
|-------|---------|
| **Daily driver check** | `./run.sh --daily-driver-check` or `./system/system.sh daily-driver` |
| Post-update validation | `./run.sh --post-update-check` or `./system/system.sh post-update-check` |
| Disk/memory summary | `./run.sh --disk-summary` or `./system/health_snapshot.sh --show` |
| Btrfs health | `./system/system.sh btrfs-health` |
| LUKS readiness | `./system/system.sh luks-readiness` |
| VirtualBox readiness | `./system/system.sh virtualbox-readiness` |
| Package / update noise | `./system/system.sh package-noise` |
| Rebuild readiness | `./run.sh --rebuild-check` or `./system/system.sh rebuild-check` |

Recovery playbook: [docs/RECOVERY.md](../docs/RECOVERY.md) · Phase 2 validation: [docs/PHASE2-VALIDATION.md](../docs/PHASE2-VALIDATION.md)

| Check | Command |
|-------|---------|
| Fresh install report | `./run.sh --baseline` or `./system/system.sh baseline` |
| Host snapshot | `./system/system.sh info` |
| Disk and memory summary | `./system/health_snapshot.sh --show` |

---

## Menu structure

```text
system/system.sh
├── [Readiness]
│   ├── [1] Daily driver check        btrfs · LUKS · VirtualBox · services
│   ├── [2] Post-update check         after dnf upgrade
│   └── [3] Rebuild readiness         pre-rebuild validation
├── [Host information]
│   ├── [4] Host snapshot             OS · kernel · hardware · mounts
│   └── [5] Disk and memory           storage · RAM · swap
│       └── More readiness checks     btrfs · LUKS · fresh install · …
├── [Operations]
│   ├── [6] Update Fedora             sudo · scroll · log
│   ├── [7] View logs                 log_engine submenu
│   └── [8] Cleanup                   logs · dnf · repo fix
├── [Security]
│   └── [9] Hardening and services    firewall · services · audit
└── [0] Back to main menu             (when opened from ./run.sh)
```

CLI shortcuts: `./system/system.sh daily-driver|post-update-check|btrfs-health|luks-readiness|virtualbox-readiness|package-noise|update|info|baseline|rebuild-check|monitor|backup|research-doctor|logs`

---

## Logs

Preferred: **`./system/log_engine.sh`** — full CLI and log file list in [logs/README.md](../logs/README.md).

---

## Doctors

Doctor matrix: [docs/GETTING-STARTED.md](../docs/GETTING-STARTED.md#doctor-matrix-no-double-runs)

| Check | Command |
|-------|---------|
| Daily driver (stabilization) | `./run.sh --daily-driver-check` (System menu `[1]`) |
| Fedora doctor (toolkit) | `./run.sh --doctor` or `./run.sh` → `[8]` |
| Full research (Android + MobSF) | `./system/system.sh research-doctor` (rebuild finale) |
| MobSF stack only | `./mobsf.sh --doctor` |

---

## Libraries used

- `lib/readiness.sh` — daily driver, btrfs, LUKS, VirtualBox, package noise probes
- `lib/health_snapshot.sh` — disk/memory summary (auto-refresh if stale; no full `du` in quick mode)

See [docs/GETTING-STARTED.md](../docs/GETTING-STARTED.md) · [docs/README.md](../docs/README.md)
