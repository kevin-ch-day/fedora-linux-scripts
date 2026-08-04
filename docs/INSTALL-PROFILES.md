# Install profiles

One-command workstation setup via **`./setup.sh`** and the shared profile engine in **`lib/profiles.sh`** / **`lib/install_engine.sh`**.

---

## Quick reference

```bash
./setup.sh list                        # catalog
./setup.sh research --plan             # numbered step plan (no sudo)
./setup.sh research --validate         # verify scripts exist
./setup.sh research --dry-run --yes    # show what would run
./setup.sh research --yes              # broad research workstation (review plan first)
```

---

## Profiles

| Profile | Steps | Optional tail |
|---------|-------|----------------|
| **research** | Quick update → post-update → Podman/KVM → standard Android core → RE install → verify | Android research doctor |
| **android-re** | Standard Android core → RE install → verify | Android RE doctor |
| **dev-stack** | VS Code → Podman/KVM (Docker opt-in) | — |
| **dev-full** | Git (skip if configured) → VS Code → Podman/KVM (Docker opt-in) | — |
| **web-stack** | LAMP → phpMyAdmin | Web stack doctor |
| **mariadb-no-start** | MariaDB packages only; no service activation or explicit initialization | — |

**research** is the broad guided workstation sequence.

---

## Environment / non-interactive notes

| Step | Non-interactive behavior |
|------|--------------------------|
| **Git** (`dev-full`) | Uses `--skip-if-configured`; set `GIT_NAME` / `GIT_EMAIL` to force configure |
| **MobSF** | Kept separate: provision and operate it through `./mobsf.sh` |
| **Doctors** | With `--yes`, runs automatically at end when profile includes one |
| **web-stack auto mode** | Requires `--yes --allow-service-start`; the plan identifies service and SELinux effects |
| **Docker** | Never selected by a broad profile; use the explicit Docker menu/flag |

---

## Fresh machine flows

```bash
./setup.sh --guided          # validate → onboard wizard (check → research setup)
./setup.sh research --yes    # skip wizard, run full stack
```

See [GETTING-STARTED.md](GETTING-STARTED.md) for doctor matrix and post-rebuild optional steps (desktop, git interactive, etc.).

---

## Adding a profile

1. Add id to `profile_list_names()` in `lib/profiles.sh`
2. Implement `profile_description`, `profile_iter_steps` rows (TSV: title, script, sudo mode, args)
3. Optionally wire `profile_wants_doctor`
4. Run `./validate.sh --quick` (profile step script check)
5. Run `./setup.sh <profile> --plan` to review

---

## Related

- [GETTING-STARTED.md](GETTING-STARTED.md) — main entry points and menu map
- [../lib/README.md](../lib/README.md) — shared libraries
- [../mobsf/GUIDE.md](../mobsf/GUIDE.md) — MobSF operations
