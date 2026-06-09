# Developer Workstation Areas

Git, VS Code, containers/KVM, VirtualBox, and optional LAMP/phpMyAdmin stack.

**Menu:** `./dev/dev.sh` · **From main entry:** `./run.sh` → `[2]` or `./run.sh --dev`

---

## Install order (typical)

```bash
# As your user (not sudo)
./dev/git_setup.sh

# Sudo steps
sudo ./dev/install_vscode.sh
sudo ./dev/desktop_setup.sh          # Cinnamon primary + GNOME/XFCE fallbacks
sudo ./dev/desktop_setup.sh --only-profiles kde --default-session plasma
sudo ./dev/fedora_container_kvm_setup.sh
sudo ./dev/virtualbox_setup.sh       # RPM Fusion Free + VirtualBox host packages

# Optional web stack (localhost by default)
sudo ./dev/lamp_python_setup.sh
sudo ./dev/phpmyadmin_setup.sh
./dev/web_stack_doctor.sh
```

Rebuild sequence runs KVM setup early: `./run.sh --rebuild`

---

## Direct menus

```text
dev/dev.sh
├── Developer tools               git · VS Code · shell helpers
├── Desktop environments          Cinnamon · KDE · MATE · LXQt
├── Virtualization & containers   Podman/KVM · Docker · VirtualBox · status
└── Web/database stack            Apache · MariaDB · PHP · phpMyAdmin
```

CLI shortcuts: `./dev/dev.sh git|vscode|desktop|desktop-kde|desktop-mate|desktop-lxqt|desktop-budgie|desktop-cosmic|desktop-sway|desktop-cinnamon|desktop-default|desktop-status|kvm|virtualbox|lamp|phpmyadmin|web-doctor`

### VirtualBox

The VirtualBox host packages are delivered through **RPM Fusion Free** on Fedora.
This toolkit installs the release repo package first when needed, then installs
`VirtualBox`, `akmod-VirtualBox`, and the kernel build prerequisites.

```bash
sudo ./dev/virtualbox_setup.sh
./dev/dev.sh virtualbox
```

If the running kernel does not match the newest `kernel-devel`, reboot into the
newest kernel and rerun the installer. Secure Boot can also block unsigned
VirtualBox kernel modules.

### Desktop environments

**Cinnamon** is still the recommended daily driver on this workstation, but the toolkit now supports additional named desktop profiles too: `gnome`, `xfce`, `kde`, `mate`, `lxqt`, `budgie`, `cosmic`, and `sway`.

Official Fedora options:

| Method | Command / link |
|--------|----------------|
| **This repo** | `sudo ./dev/desktop_setup.sh` — Cinnamon primary + GNOME/XFCE recovery sessions + optional default session |
| **dnf only** | `sudo dnf install @cinnamon-desktop` then pick Cinnamon on the login screen |
| **Live spin** | [Fedora Cinnamon Spin](https://spins.fedoraproject.org/) (try or install Cinnamon-only media) |
| **Netinstall** | Select the Cinnamon desktop group during a netinstall |

This toolkit wraps the dnf group install and adds fallbacks for recovery:

```bash
sudo ./dev/desktop_setup.sh              # Cinnamon primary + GNOME/XFCE recovery; sets Cinnamon default
sudo ./dev/desktop_setup.sh --cinnamon-only
sudo ./dev/desktop_setup.sh --only-profiles kde --default-session plasma
sudo ./dev/desktop_setup.sh --only-profiles mate,lxqt,budgie
sudo ./dev/desktop_setup.sh --profiles cosmic,sway --skip-default
sudo ./dev/desktop_setup.sh --set-default   # Cinnamon default only (no install)
sudo ./dev/desktop_setup.sh --default-session plasma   # switch default only
./dev/desktop_setup.sh --status           # list sessions (no sudo)
```

After install: log out → login screen → session menu (gear icon) → pick the session you want. Common session names are `cinnamon`, `gnome`, `xfce`, `plasma`, `mate`, `lxqt`, `budgie-desktop`, `cosmic`, and `sway`.

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

Web stack doctor: `./dev/web_stack_doctor.sh` · Fedora doctor: `./run.sh --doctor` · Full research: `./system/research_doctor.sh`

---

See [docs/GETTING-STARTED.md](../docs/GETTING-STARTED.md) · [docs/README.md](../docs/README.md)
