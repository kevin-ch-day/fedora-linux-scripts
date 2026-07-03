# System maintenance lane

Host maintenance, workstation readiness, updates, logs, and cleanup for Fedora research workstations.

**Menu:** `./system/system.sh` · **From main entry:** `./run.sh` → `[6]` or `./run.sh --system`

---

## Workstation readiness (read-only by default)

| Check | Command |
|-------|---------|
| **Daily driver check** | `./run.sh --daily-driver-check` or System menu `[5]` |
| **Daily sync** | `./run.sh --daily` or main menu `[2]` / System menu `[2]` |
| Post-update validation | `./run.sh --post-update-check` or System menu `[3]` |
| Disk/memory summary | `./run.sh --disk-summary` or System menu `[8]` |
| Btrfs health | System menu `[8]` → More readiness → `[1]` |
| LUKS readiness | System menu `[8]` → More readiness → `[2]` |
| VirtualBox readiness | System menu `[8]` → More readiness → `[3]` |
| Package / update noise | System menu `[8]` → More readiness → `[4]` |
| Rebuild readiness | `./run.sh --rebuild-check` or System menu `[6]` |

Recovery playbook: [docs/RECOVERY.md](../docs/RECOVERY.md) · Phase 2 validation: [docs/PHASE2-VALIDATION.md](../docs/PHASE2-VALIDATION.md)

| Check | Command |
|-------|---------|
| Fresh install report | `./run.sh --baseline` or More readiness → `[5]` |
| Host snapshot | System menu `[7]` |
| Disk and memory summary | System menu `[8]` |

---

## Menu structure

```text
system/system.sh  (also ./run.sh → [6])
├── [Updates — start here]
│   ├── [1] Update Fedora
│   ├── [2] Update + post-update check   ← daily workflow
│   ├── [3] Post-update check only
│   └── [4] Quick update
├── [Readiness]
│   ├── [5] Daily driver check
│   └── [6] Rebuild readiness
├── [Host information]
│   ├── [7] Host snapshot
│   └── [8] Disk and memory → More readiness (btrfs · LUKS · …)
├── [Operations]
│   ├── [9] View logs
│   └── [10] Cleanup → [6] Fix DNF repo permissions
└── [Security]
    └── [11] Hardening and security
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
| Daily driver (stabilization) | `./run.sh --daily-driver-check` (System menu `[5]`) |
| Fedora doctor (toolkit) | `./run.sh --doctor` or main menu `[7]` |
| Full research (Android + MobSF) | `./system/system.sh research-doctor` (rebuild finale) |
| MobSF stack only | `./mobsf.sh --doctor` |

---

## Libraries used

- `lib/readiness.sh` — daily driver, btrfs, LUKS, VirtualBox, package noise probes
- `lib/health_snapshot.sh` — disk/memory summary (auto-refresh if stale; no full `du` in quick mode)
