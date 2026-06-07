# Fedora Toolkit — Maintainer Audit

**Repo:** `fedora-linux-scripts` · **Updated:** 2026-06-07  
**Operator guide:** [GETTING-STARTED.md](GETTING-STARTED.md) · **Script index:** [README.md](../README.md)

---

## Health snapshot

| Check | Status |
|-------|--------|
| `bash -n` (active scripts) | Pass |
| ShellCheck `-S warning` | Pass (`./validate.sh`) |
| Entry points | `./fedora.sh`, `./mobsf.sh`, `./validate.sh` · checks in `lib/entry_points.sh` |
| CI | `.github/workflows/validate.yml` |
| Docs | `docs/GETTING-STARTED.md`, `mobsf/GUIDE.md` |

```text
fedora.sh → system/ · dev/ · android/ + rebuild + doctor
mobsf.sh  → mobsf/mobsf.sh (separate Podman stack)
lib/      → shared helpers · mobsf/lib/ → stack-specific
```

Scale: ~45 active task scripts · 15 lib modules · 4 lane menus.

---

## Security matrix (resolved)

| Finding | Severity | Status |
|---------|----------|--------|
| phpMyAdmin remote by default | High | **Fixed** — `--allow-remote` opt-in |
| Public `info.php` by default | High | **Fixed** — `--with-info-php` opt-in |
| Hardcoded git PII | High | **Fixed** — env/prompt |
| MobSF data dirs `0777` | High | **Fixed** — default `0770` |
| Compose DB password hardcoded | Medium | **Fixed** — `${POSTGRES_PASSWORD}` + `.env` |
| LAN-visible compose ports | High | **Fixed** — bind `127.0.0.1` |
| Orphan cleanup removed all containers | Critical | **Fixed** — MobSF scope filter |
| Legacy scripts runnable | Critical | **Fixed** — `exit 1` guards |

No `eval` or `curl|bash` in active scripts.

---

## ShellCheck & validation

```bash
./validate.sh                    # syntax + entry points + docs + optional ShellCheck
./validate.sh --shellcheck       # CI-equivalent
```

Baseline: **0 warnings** at `-S warning` (excluding `legacy/`).

---

## Open / low-priority items

| Area | Item | Notes |
|------|------|-------|
| MobSF | Start uses sudo in menu | SELinux relabel on first start |
| MobSF | start/stop/doctor lack log sessions | install/reset/update log to `mobsf.log` |
| Android | SDK zip URL pinned | no auto-upgrade path in core setup |
| Android | `bash -lc` in verify | rare BASH_ENV edge case |
| System | `system_update.sh` | uses `pkg_emit` + log engine; `--quick` for menu/rebuild |
| UX | Compact headers / fewer redraws | scroll mode helps |

Consolidation (RE engine, lane launchers, MobSF split, secrets, autostart, dynamic doctor, doc merges) is **complete**.

---

## Menu UX reference

### Legend

| Symbol | Meaning |
|--------|---------|
| **pause** | Return to same menu after Enter |
| **scroll** | Output kept above (no clear) |
| **sudo** / **sudo -E** | Elevated run (MobSF preserves env) |
| **confirm** | Destructive action confirmation |
| **soft-fail** | Warn and stay in menu |
| `[0]` | Back · `[r]` | Repeat last choice |

### Lane picker (`fedora.sh`)

```
[1] System  [2] Dev  [3] Android  [4] Rebuild  [5] Doctor  [0] Exit
```

MobSF is a separate entry: `./mobsf.sh`

CLI shortcuts exit to shell (by design): `./fedora.sh 1`–`3`, `--system`, `--dev`, `--android`, `--doctor`, `--rebuild*`

### MobSF menu (`./mobsf.sh`)

```
[1] Stack  [2] Setup  [3] Doctor  [4] Maintenance  [5] Logs  [6] Docs  [0] Exit
```

### Dev lane (`./fedora.sh --dev`)

Workstation: git · VS Code · Cinnamon (`@cinnamon-desktop`) · `--cinnamon-only` · `--set-default` · status. Infrastructure: KVM. Web: LAMP/phpMyAdmin.

Full trees were trimmed here; source of truth is `*/lib/menu.sh`. QA loop:

```bash
./fedora.sh
./fedora.sh --rebuild --dry-run
./fedora.sh 1    # exits to shell when non-interactive — expected
```

---

## Test checklist

```bash
./validate.sh
./fedora.sh --doctor
./mobsf.sh --doctor
./system/research_doctor.sh --android-only
./legacy/update_fedora.sh          # must exit 1
./android/verify_dex2jar_install.sh
```

---

## See also

- [GETTING-STARTED.md](GETTING-STARTED.md) — doctors, shims, rebuild sequence
- [mobsf/GUIDE.md](../mobsf/GUIDE.md) · [mobsf/TROUBLESHOOTING.md](../mobsf/TROUBLESHOOTING.md)
- [logs/README.md](../logs/README.md)
