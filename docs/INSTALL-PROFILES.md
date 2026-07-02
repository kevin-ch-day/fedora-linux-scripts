# Install profiles

One-command workstation setup via **`./install.sh`** and the shared profile engine in **`lib/profiles.sh`** / **`lib/install_engine.sh`**.

---

## Quick reference

```bash
./install.sh list                      # catalog
./install.sh research --plan           # numbered step plan (no sudo)
./install.sh research --validate       # verify scripts exist
./install.sh research --dry-run --yes  # show what would run
./install.sh research --yes            # full research workstation
./run.sh --profile dev-full --yes      # same as install.sh
./run.sh --rebuild --plan              # research plan (compat)
```

---

## Profiles

| Profile | Steps | Optional tail |
|---------|-------|----------------|
| **research** | Quick update → post-update → KVM → Android core → RE install → verify | MobSF install · research doctor |
| **android-re** | Android core → RE install → verify | Android RE doctor |
| **dev-stack** | VS Code → containers/KVM | — |
| **dev-full** | Git (skip if configured) → VS Code → containers/KVM | — |
| **web-stack** | LAMP → phpMyAdmin | Web stack doctor |
| **mobsf** | MobSF Podman install | MobSF doctor |
| **daily-sync** | Full update → post-update check | — |
| **update-only** | Full Fedora update | — |

**research** is the same sequence as **`./run.sh --rebuild`** (default profile).

---

## Environment / non-interactive notes

| Step | Non-interactive behavior |
|------|--------------------------|
| **Git** (`dev-full`) | Uses `--skip-if-configured`; set `GIT_NAME` / `GIT_EMAIL` to force configure |
| **MobSF** (`research`) | With `--yes`, installs only when compose is missing |
| **Doctors** | With `--yes`, runs automatically at end when profile includes one |

---

## Fresh machine flows

```bash
./setup.sh --guided          # validate → onboard wizard (check → rebuild)
./run.sh --onboard           # setup → check → optional rebuild
./install.sh research --yes  # skip wizard, run full stack
```

See [GETTING-STARTED.md](GETTING-STARTED.md) for doctor matrix and post-rebuild optional steps (desktop, git interactive, etc.).

---

## Adding a profile

1. Add id to `profile_list_names()` in `lib/profiles.sh`
2. Implement `profile_description`, `profile_iter_steps` rows (TSV: title, script, sudo mode, args)
3. Optionally wire `profile_wants_mobsf` / `profile_wants_doctor`
4. Run `./validate.sh --quick` (profile step script check)
5. Run `./install.sh <profile> --plan` to review

---

## Related

- [GETTING-STARTED.md](GETTING-STARTED.md) — main entry points and menu map
- [../lib/README.md](../lib/README.md) — shared libraries
- [../mobsf/GUIDE.md](../mobsf/GUIDE.md) — MobSF operations
