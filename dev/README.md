# Dev Workstation Lane

Git, VS Code, containers/KVM, and optional LAMP/phpMyAdmin stack.

**Menu:** `./dev/dev.sh` · **From main entry:** `./fedora.sh` → `[2]` or `./fedora.sh --dev`

---

## Install order (typical)

```bash
# As your user (not sudo)
./dev/git_setup.sh

# Sudo steps
sudo ./dev/install_vscode.sh
sudo ./dev/desktop_setup.sh          # Cinnamon primary + GNOME/XFCE fallbacks
sudo ./dev/fedora_container_kvm_setup.sh

# Optional web stack (localhost by default)
sudo ./dev/lamp_python_setup.sh
sudo ./dev/phpmyadmin_setup.sh
./dev/web_stack_doctor.sh
```

Rebuild sequence runs KVM setup early: `./fedora.sh --rebuild`

---

## Menu structure

```text
dev/dev.sh
├── [1] Workstation       git · VS Code · Cinnamon + fallbacks · desktop status
├── [2] Infrastructure    Podman/KVM · research service status
└── [3] Web stack         LAMP · phpMyAdmin · doctor · remove info.php
```

CLI shortcuts: `./dev/dev.sh git|vscode|desktop|desktop-cinnamon|desktop-default|desktop-status|kvm|lamp|phpmyadmin|web-doctor`

### Desktop environments (Cinnamon)

**Cinnamon** is the recommended daily driver on this workstation — traditional layout, maintained by the Linux Mint project and packaged for Fedora as `@cinnamon-desktop`.

Official Fedora options:

| Method | Command / link |
|--------|----------------|
| **This repo** | `sudo ./dev/desktop_setup.sh` — `@cinnamon-desktop` + GNOME/XFCE fallbacks + optional default session |
| **dnf only** | `sudo dnf install @cinnamon-desktop` then pick Cinnamon on the login screen |
| **Live spin** | [Fedora Cinnamon Spin](https://spins.fedoraproject.org/) (try or install Cinnamon-only media) |
| **Netinstall** | Select the Cinnamon desktop group during a netinstall |

This toolkit wraps the dnf group install and adds fallbacks for recovery:

```bash
sudo ./dev/desktop_setup.sh              # Cinnamon + GNOME + XFCE; sets Cinnamon default
sudo ./dev/desktop_setup.sh --cinnamon-only
sudo ./dev/desktop_setup.sh --set-default   # Cinnamon default only (no install)
./dev/desktop_setup.sh --status           # list sessions (no sudo)
```

After install: log out → login screen → session menu (gear icon) → **Cinnamon**. More: [Fedora Wiki — Cinnamon](https://fedoraproject.org/wiki/Cinnamon) · [Cinnamon Spices](https://cinnamon-spices.linuxmint.com/) (themes, applets, extensions).

---

## Security defaults

| Script | Default | Opt-in risky flags |
|--------|---------|-------------------|
| `phpmyadmin_setup.sh` | `Require local` (127.0.0.1) | `--allow-remote` |
| `lamp_python_setup.sh` | No public phpinfo | `--with-info-php` |
| `git_setup.sh` | Identity from env or prompt | — |

Remove test phpinfo after LAMP verify:

```bash
sudo ./dev/lamp_python_setup.sh --remove-info-php
```

Or: dev menu → Web stack → [4] Remove public info.php

---

Web stack doctor: `./dev/web_stack_doctor.sh` · Fedora doctor: `./fedora.sh --doctor` · Full research: `./system/research_doctor.sh`

---

See [docs/GETTING-STARTED.md](../docs/GETTING-STARTED.md) · [docs/README.md](../docs/README.md)
