# Dev Workstation Lane

Git, VS Code, containers/KVM, and optional LAMP/phpMyAdmin stack.

**Menu:** `./dev/dev.sh` · **From picker:** `./fedora.sh` → [2]

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

Rebuild sequence runs KVM setup early: `./fedora_rebuild.sh`

---

## Menu structure

```text
dev/dev.sh
├── [1] Workstation       git · VS Code · Cinnamon + fallbacks · desktop status
├── [2] Infrastructure    Podman/KVM · research service status
└── [3] Web stack         LAMP · phpMyAdmin · doctor · remove info.php
```

CLI shortcuts: `./dev/dev.sh git|vscode|desktop|desktop-status|kvm|lamp|phpmyadmin|web-doctor`

### Desktop environments

Cinnamon is the recommended daily driver. The setup script also installs **GNOME** and **XFCE** as fallbacks — pick any session from the gear icon on the login screen.

```bash
sudo ./dev/desktop_setup.sh              # install all
sudo ./dev/desktop_setup.sh --cinnamon-only
./dev/desktop_setup.sh --status
```

Switch session without reinstalling: log out → login screen → session menu → Cinnamon / GNOME / XFCE.

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

## Doctors & status

| Command | Purpose |
|---------|---------|
| `./dev/web_stack_doctor.sh` | Apache/MariaDB/PHP/phpMyAdmin HTTP checks |
| `./dev/dev.sh` → Infrastructure [2] | Research stack service status (via `lib/services.sh`) |

Full Android + MobSF doctor: `./system/research_doctor.sh`

---

## Libraries used

- `lib/packages.sh` — DNF install helpers
- `lib/services.sh` — systemctl, LAMP/MobSF container status

See [GETTING-STARTED.md](../GETTING-STARTED.md) · [CONSOLIDATION.md](../CONSOLIDATION.md) and [README.md](../README.md).
