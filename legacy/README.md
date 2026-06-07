# Legacy scripts

**Status:** Archived reference only. Scripts are **hard-disabled** (`exit 1` at top).  
They are **not** in `./fedora.sh` or any lane menu — use the replacements below.

Do not run on a fresh Fedora install.

| Script | Replacement |
|--------|-------------|
| `update_fedora.sh` | `../system/system_update.sh` |
| `setup_dev_env.sh` | `../android/android_dev_core_setup.sh` + user-scoped pip |
| `FedoraInstallApps.sh` | `../dev/` scripts and `../android/` installers |
