# Android RE Lane

Quick reference for the Android security / reverse-engineering workstation on Fedora.

**Menu:** `./android/android.sh` · **From main entry:** `./run.sh --android`

**MobSF** (separate lifecycle): `./mobsf.sh` — not part of this lane.

---

## Verification tiers

| Tier | Command | Scope |
|------|---------|--------|
| **Core tools** | `./android/android_dev_core_setup.sh --status` | adb, java, sdkmanager, frida, objection, mitmproxy, node/npm (read-only) |
| **APK RE tools** | `./android/verify_all_re_tools.sh` | apktool, jadx, smali, dex2jar |
| **Full doctor** | `./android/doctor_android_research.sh` | Core + ADB + all RE tools |
| **MobSF stack** | `./mobsf.sh` · `./mobsf.sh --doctor` | Podman stack only |

---

## Install order

The menu’s first option runs the complete `android-re` profile: standard core,
all APK reverse-engineering tools, then verification.

```bash
./install.sh android-re
```

The equivalent direct sequence is:

```bash
sudo -E ./android/android_dev_core_setup.sh --preset standard
./android/android_re_install.sh all
./android/verify_re_tool.sh all
./android/doctor_android_research.sh
```

Full research doctor (Android **+** MobSF): `./system/research_doctor.sh` or `./android/android.sh research-doctor`

Fedora doctor (entry points · Android RE, no MobSF): `./run.sh --doctor`

---

## Preferred CLIs

| Task | Command |
|------|---------|
| Preview standard core | `./android/android.sh plan standard` |
| Preview headless core | `./android/android.sh plan minimal` |
| Install standard core | `./android/android.sh core standard` |
| Install minimal core | `./android/android.sh core minimal` |
| Install full core | `./android/android.sh core full` |
| Core status (read-only) | `./android/android_dev_core_setup.sh --status` |
| Repair SDK shell PATH only | `./android/android_dev_core_setup.sh --repair-shell` |
| Install all APK tools | `./android/android.sh apk-install` |
| Install one APK tool | `./android/android.sh apk-install jadx` |
| Upgrade / re-fetch | `./android/android.sh apk-upgrade jadx` |
| Verify one | `./android/verify_re_tool.sh apktool` |
| Verify all APK RE | `./android/verify_all_re_tools.sh` |
| ADB status | `./android/android.sh` → ADB and device checks |

Install logic: `lib/android_re.sh`  
Verify logic: `lib/android.sh` (via `verify_re_tool.sh`)

Node/npm are **optional** for core setup; required only for **apk-mitm** (Repair Node/npm menu item).

---

## Core presets

The core installer is capability-based so the same lane works on different
Fedora host roles.

| Preset | Intended host | Included |
|--------|---------------|----------|
| `minimal` | Headless VM, lab node, device-only host | Java, adb/fastboot, Android SDK command-line tools, managed PATH |
| `standard` | Normal graphical RE workstation | Minimal + Python RE tools, Wireshark, Android Studio |
| `full` | Workstation that also needs apk-mitm | Standard + Node/npm and apk-mitm |

`standard` is the default. All presets are idempotent and can be adjusted:

```bash
./android/android_dev_core_setup.sh --preset standard --plan

sudo -E ./android/android_dev_core_setup.sh \
  --preset standard \
  --without-studio \
  --without-shell-rc

sudo -E ./android/android_dev_core_setup.sh \
  --preset minimal \
  --sdk-root "$HOME/.local/share/android-sdk"
```

Component flags are `--with-*` / `--without-*` for `studio`, `python`, `node`,
`wireshark`, `sdk`, and `shell-rc`. Explicit component flags override the
preset regardless of argument order.

The installer remains Fedora-specific for system packages. Presets make it
portable across Fedora Workstation, headless Fedora, VMs, and differently
provisioned hosts; they do not claim support for unrelated distributions.

The SDK root must be an absolute directory inside the target user’s home.
The default is `~/Android/Sdk`. `ANDROID_HOME` is written to the managed shell
block; deprecated `ANDROID_SDK_ROOT` is no longer added. Existing SDK paths can
be selected with `--sdk-root`.

The command-line tools build is pinned for repeatability and can be overridden
with `--cmdline-tools-version`. The current default is `14742923`.

---

## Menu design

The landing page contains direct outcomes instead of opening a second “core
setup” menu:

1. complete standard Android RE workstation;
2. standard core only;
3. APK RE tools only;
4. minimal/headless core;
5. workstation doctor;
6. ADB/device checks.

Plans, upgrades, individual tools, Node repair, and the combined MobSF brief
live under one **Advanced tools and plans** page.

---

## Legacy shims (still work)

- `android_re_*_user_install.sh` → `android_re_install.sh TOOL`
- `verify_*_install.sh` → `verify_re_tool.sh TOOL`

---

## After install

If the selected run managed shell configuration:

```bash
source ~/.bashrc
```

Tools land in `~/.local/bin` and `~/.local/opt/`.

Official references:

- [Android SDK command-line tools](https://developer.android.com/tools/sdkmanager)
- [Android environment variables](https://developer.android.com/tools/variables)
- [Android Studio and command-line tool downloads](https://developer.android.com/studio)

See [docs/GETTING-STARTED.md](../docs/GETTING-STARTED.md) · [docs/README.md](../docs/README.md)
