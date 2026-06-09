# Android RE Lane

Quick reference for the Android security / reverse-engineering workstation on Fedora.

**Menu:** `./android/android.sh` · **From main entry:** `./run.sh` → `[6]` or `./run.sh --android`

**MobSF** (separate lifecycle): `./mobsf.sh` — not part of this lane.

---

## Verification tiers

| Tier | Command | Scope |
|------|---------|--------|
| **Core tools** | `sudo ./android/android_dev_core_setup.sh --status` | adb, java, sdkmanager, frida, objection, mitmproxy, node/npm (read-only) |
| **APK RE tools** | `./android/verify_all_re_tools.sh` | apktool, jadx, smali, dex2jar |
| **Full doctor** | `./android/doctor_android_research.sh` | Core + ADB + all RE tools |
| **MobSF stack** | `./mobsf.sh` · `./mobsf.sh --doctor` | Podman stack only |

---

## Install order

See [docs/GETTING-STARTED.md](../docs/GETTING-STARTED.md) for full rebuild flow. Lane sequence:

```bash
sudo ./android/android_dev_core_setup.sh
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
| Core status (read-only) | `sudo ./android/android_dev_core_setup.sh --status` |
| Install one tool | `./android/android_re_install.sh jadx` |
| Upgrade / re-fetch | `./android/android_re_install.sh --upgrade jadx` |
| Upgrade from menu | `./run.sh --android` → RE tool installs → items 11–15 |
| Install all | `./android/android_re_install.sh all` |
| Verify one | `./android/verify_re_tool.sh apktool` |
| Verify all APK RE | `./android/verify_all_re_tools.sh` |
| ADB status | `./android/android.sh` → ADB and device checks |

Install logic: `lib/android_re.sh`  
Verify logic: `lib/android.sh` (via `verify_re_tool.sh`)

Node/npm are **optional** for core setup; required only for **apk-mitm** (Repair Node/npm menu item).

---

## Legacy shims (still work)

- `android_re_*_user_install.sh` → `android_re_install.sh TOOL`
- `verify_*_install.sh` → `verify_re_tool.sh TOOL`

---

## After install

```bash
source ~/.bashrc   # or log out/in for PATH
```

Tools land in `~/.local/bin` and `~/.local/opt/`.

See [docs/GETTING-STARTED.md](../docs/GETTING-STARTED.md) · [docs/README.md](../docs/README.md)
