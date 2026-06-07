# Android RE Lane

Quick reference for the Android security / reverse-engineering workstation on Fedora.

**Menu:** `./android/android.sh` · **From picker:** `./fedora.sh` → [3]

---

## Install order

```bash
# 1. Core stack (sudo) — Java, SDK, Frida, ADB, pip tools
sudo ./android/android_dev_core_setup.sh

# 2. RE tools (user scope → ~/.local/)
./android/android_re_install.sh all

# 3. Verify
./android/verify_re_tool.sh all

# 4. Android-only doctor
./android/doctor_android_research.sh
```

Full research doctor (Android **+** MobSF): `./system/research_doctor.sh`

---

## Preferred CLIs

| Task | Command |
|------|---------|
| Install one tool | `./android/android_re_install.sh jadx` |
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

See [GETTING-STARTED.md](../GETTING-STARTED.md) · [CONSOLIDATION.md](../CONSOLIDATION.md)
