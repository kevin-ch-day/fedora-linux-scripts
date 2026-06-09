# Android RE Lane

Quick reference for the Android security / reverse-engineering workstation on Fedora.

**Menu:** `./android/android.sh` · **From main entry:** `./run.sh` → `[3]` or `./run.sh --android`

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
| Install one tool | `./android/android_re_install.sh jadx` |
| Upgrade / re-fetch | `./android/android_re_install.sh --upgrade jadx` |
| Upgrade from menu | `./run.sh --android` → RE tool installs → items 11–15 |
| Install all | `./android/android_re_install.sh all` |
| Verify one | `./android/verify_re_tool.sh apktool` |
| Verify all | `./android/verify_re_tool.sh all` |
| ADB status | `./android/android.sh` → Diagnostics → ADB |

Install logic: `lib/android_re.sh`  
Verify logic: `lib/android.sh` (via `verify_re_tool.sh`)

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
