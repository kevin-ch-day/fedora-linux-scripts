# Fedora Toolkit — Consolidation Guide

**Purpose:** One map for entry points, doctors, logs, and merge status.  
**See also:** [AUDIT.md](AUDIT.md), [AUDIT-CODE.md](AUDIT-CODE.md)

---

## Entry points (use these)

| Goal | Command |
|------|---------|
| Daily lane menus | `./fedora.sh` |
| Full guided rebuild | `./fedora_rebuild.sh` (not a fedora.sh submenu) |
| Quick orientation | [GETTING-STARTED.md](GETTING-STARTED.md) |
| System lane | `./system/system.sh` |
| Dev lane | `./dev/dev.sh` |
| Android lane | `./android/android.sh` |
| MobSF lane | `./mobsf/mobsf.sh` |
| Full research doctor | `./system/research_doctor.sh` or `./fedora.sh --doctor` |
| Logs CLI | `./system/log_engine.sh` or `./system/system.sh logs` |

---

## Doctor matrix (no double-runs)

| Script | Scope | When to use |
|--------|-------|-------------|
| `system/research_doctor.sh` | Android **+** MobSF (full) | After rebuild; `fedora.sh --doctor`; System menu [4] |
| Orchestration | `lib/research.sh` | `research_doctor_run()` |
| `android/doctor_android_research.sh` | Android only | Android lane menu; quick RE check |
| `mobsf/mobsf_doctor.sh` | MobSF only (full) | MobSF lane; `./mobsf/mobsf.sh --doctor` |
| `dev/web_stack_doctor.sh` | LAMP / phpMyAdmin | After dev stack install |

**Do not run** Android doctor and `research_doctor.sh` back-to-back — rebuild ends with **research doctor only**.

---

## Logs (single CLI)

| Preferred | Deprecated |
|-----------|------------|
| `./system/log_engine.sh tail --file NAME --lines N` | `./system/view_logs.sh` (legacy flag shim) |

Log files: `system_update.log`, `fedora_rebuild.log`, `android_dev_core.log`, `mobsf.log`

---

## Verify RE tools

| Preferred | Legacy (shim) |
|-----------|---------------|
| `./android/verify_re_tool.sh apktool` | `./android/verify_apktool_install.sh` |
| `./android/verify_re_tool.sh all` | `./android/verify_all_re_tools.sh` |

## Install RE tools

| Preferred | Legacy (exec shim) |
|-----------|-------------------|
| `./android/android_re_install.sh all` | `android_re_*_user_install.sh` |
| `./android/android_re_install.sh jadx` | same pattern |

Install logic: **`lib/android_re.sh`**. Host snapshot: **`health_print_system_info()`** in `lib/health.sh`.

---

## Menu overlap resolved

| Area | Location |
|------|----------|
| Host snapshot / monitor / disk | System lane → Host visibility |
| Update / backup / cleanup | System lane → Maintenance |
| Logs tail / follow / issues | System lane → Logs |
| Research doctor (full) | System lane [4] or `fedora.sh --doctor` |
| LAMP / phpMyAdmin doctor | Dev lane → Web stack doctor |
| Android RE doctor | Android lane |

**Removed from `fedora.sh` v0.5.0:** rebuild submenu, legacy item — use `./fedora_rebuild.sh` and `legacy/README.md` instead.

---

## Lane launchers (pattern)

```text
fedora.sh          → lane picker (exit lane → return here); execs */lane.sh as child
fedora_rebuild.sh  → guided rebuild (standalone mode menu)
system/system.sh   → system/lib/menu.sh
dev/dev.sh         → dev/lib/menu.sh
android/android.sh → android/lib/menu.sh
mobsf/mobsf.sh     → mobsf/lib/menu.sh
```

---

## Planned merges

| Item | Status |
|------|--------|
| `lib/android_re.sh` unified RE installer (shared logic) | **Done** |
| `dev/dev.sh` + `system/system.sh` lane launchers | **Done** |
| `fedora.sh` slim router | **Done** (v0.5.1 lane picker with return) |
| `android_re_install.sh` CLI | **Done** |
| `system_monitor.sh` → `lib/health.sh` metrics | **Done** (CPU, load, memory, swap) |
| `system_info.sh` presentation | **Done** — `health_print_system_info()` |
| RE install per-tool scripts | **Done** — exec shims |
| `lib/research.sh` research doctor orchestration | **Done** |
| `view_logs.sh` legacy mapping → `lib/logging.sh` | **Done** (thin shim) |
| Lane READMEs (`system/`, `dev/`, `android/`) | **Done** |
| MobSF data dir mode | **Done** — 0770 default in `mobsf/lib/paths.sh` |
| `log_engine.sh` option order | **Done** — global flags before/after command |
| Legacy script bodies | Hard-disabled (`exit 1`) |

---

## Rebuild sequence (v0.3.2+)

1. System update  
2. Containers + KVM  
3. Android core  
4. RE tools install (`android_re_install.sh all`)  
5. Verify all RE tools  
6. *(optional)* MobSF install  
7. **Research doctor** (Android + MobSF)

Skip doctor: `./fedora_rebuild.sh --skip-doctor`
