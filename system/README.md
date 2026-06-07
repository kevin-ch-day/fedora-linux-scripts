# System Lane

Host maintenance, snapshots, logs, baseline checks, and cleanup.

**Menu:** `./system/system.sh` · **From main entry:** `./fedora.sh` → `[1]` or `./fedora.sh --system`

Fedora doctor (entry points · Android RE) lives on the **main menu** `./fedora.sh` → `[5]`, not in this lane.

---

## Quick commands

| Task | Command |
|------|---------|
| **All-in-one readiness** | `./fedora.sh --check` |
| Fix repos then re-check | `./fedora.sh --check --fix-repos` (sudo) |
| Host snapshot | `./system/system_info.sh` |
| Fresh install baseline | `./fedora.sh --baseline` or `./system/fresh_install_check.sh` |
| Rebuild readiness | `./fedora.sh --rebuild-check` or `./system/rebuild_readiness_check.sh` |
| Full Fedora update | `sudo ./system/system_update.sh --quick` |
| Fix DNF repo permissions | `sudo ./system/fix_dnf_repo_permissions.sh` |
| **OS hardening Round 1** | `./system/hardening_round1.sh --yes` |
| Round 1 status | `./system/hardening_round1.sh --status` |
| **Security audit (read-only)** | `./system/security_audit.sh` |
| Audit summary (fast) | `./system/security_audit.sh --summary` |
| Live findings only | `./system/security_audit.sh --findings` |
| Action plan | `./system/security_audit.sh --plan` |
| Compare vs previous | `./system/security_audit.sh --findings --compare` |
| Host context snapshot | `./system/host_context.sh --summary` |
| Save context history | `./system/host_context.sh --save` |
| Compare context | `./system/host_context.sh --compare` |

Context libraries: see [lib/README.md](../lib/README.md) (`users`, `network`, `system_state`, `host_context`).
| **Listening hardening** | `./system/hardening_listening.sh --yes` |
| **Strict firewall (SSH only)** | `./system/hardening_firewall_strict.sh --yes` |
| **OS hardening Round 2** | `./system/hardening_round2.sh --yes` (strict · ssh only) |
| Round 2 status | `./system/hardening_round2.sh --status` |
| **Wired only (BT/Wi-Fi off)** | `./system/hardening_wired_only.sh --yes` |
| Services audit (Round 2 prep) | `./system/hardening_services_audit.sh` |
| Live monitor | `./system/system_monitor.sh` |
| Backup state (pre-reinstall) | `./system/backup_state.sh` |
| Logs CLI | `./system/log_engine.sh status` |
| Full research (Android + MobSF) | `./system/research_doctor.sh` or `./system/system.sh research-doctor` |
| MobSF stack only | `./mobsf.sh --doctor` |
| Guided rebuild | `./fedora.sh --rebuild` |

---

## Menu structure

```text
system/system.sh
├── [1] Host information          system snapshot
├── [2] Fresh install baseline    report → logs/
├── [3] Rebuild readiness         pre-rebuild validation
├── [4] Update Fedora             sudo · scroll · log
├── [5] View logs                 log_engine submenu
├── [6] Backup current state      export for reinstall
├── [7] Cleanup                   logs · dnf · repo fix
├── [8] OS hardening              Round 1 · services audit
└── [0] Back to main menu         (when opened from ./fedora.sh)
```

CLI shortcuts: `./system/system.sh update|info|baseline|rebuild-check|monitor|backup|research-doctor|logs`

---

## Logs

Preferred: **`./system/log_engine.sh`** — full CLI and log file list in [logs/README.md](../logs/README.md).

---

## Doctors

Doctor matrix: [docs/GETTING-STARTED.md](../docs/GETTING-STARTED.md#doctor-matrix-no-double-runs)

| Check | Command |
|-------|---------|
| Fedora doctor (daily) | `./fedora.sh --doctor` or `./fedora.sh` → `[5]` |
| Full research (Android + MobSF) | `./system/system.sh research-doctor` (rebuild finale) |
| MobSF stack only | `./mobsf.sh --doctor` |

---

## Libraries used

- `lib/health.sh` — metrics, `health_print_system_info()`
- `lib/baseline.sh` — fresh-install baseline + rebuild readiness helpers
- `lib/theme.sh` — console styling for menus and summaries
- `lib/logging.sh` — log_engine + `logging_view_logs_legacy()`
- `lib/packages.sh` — DNF helpers (update, cleanup)
- `lib/research.sh` — combined research doctor
