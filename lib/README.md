# lib/ — shared toolkit libraries

Bash modules sourced by lane scripts (`system/`, `dev/`, `android/`, `mobsf/`).
Do not execute directly — each file guards with `FEDORA_*_SH_LOADED`.

## Layer map

```
common.sh          Base helpers (paths, messaging, real_user, sudo)
theme.sh           Console colors and menu styling (lane accents, gauges, status lines)
logging.sh         Report paths under logs/ or /data/logs/
health.sh          Host identity, CPU/RAM/disk, basic network
services.sh        systemd unit visibility, web stack doctor
users.sh           Login/wheel accounts, SSH session context
network.sh         Listeners, nmcli, firewalld zones
system_state.sh    SELinux, mounts, sudo/tools capability
host_context.sh    Unified snapshot (users + network + system)
hardening.sh       Round 1/2 actions (uses all context libs)
security_audit.sh  Smart audit findings (uses host_context)
baseline.sh        Fresh-install / rebuild readiness
check.sh           run.sh --check orchestration
readiness.sh       Daily driver · btrfs · LUKS · VirtualBox · package noise
```

## Host awareness API

**Quick snapshot (machine-readable):**

```bash
source lib/host_context.sh
host_context_snapshot          # key=value lines
host_context_save_snapshot     # persist under logs/host_context/<host>/
host_context_compare_snapshots # diff live vs saved file
host_context_posture_summary   # one-line research posture
host_context_print_summary     # human multi-line
host_context_print_banner      # themed one-liner block for menus
host_context_is_research_host  # Neptune-style vs desktop
```

**Network (smart listeners):**

```bash
network_unexpected_public_listeners  # all public except SSH :22
network_research_listening_issues    # one issue per line for research hosts
```

**Users:**

```bash
source lib/users.sh
users_detect_login             # space-separated login names
users_detect_wheel
users_session_kind             # local | ssh | headless
users_foreach_login_account    # user:uid:gid:home:shell
```

**Network:**

```bash
source lib/network.sh
network_public_listeners
network_listener_summary       # public=N localhost=M
network_firewall_default_zone
network_firewall_zone_is_strict [zone]
network_wired_ethernet_connected
```

**System:**

```bash
source lib/system_state.sh
system_state_selinux_mode
system_state_data_mounted
system_state_sudo_passwordless
system_state_log_root [subdir]
```

## Environment overrides

| Variable | Effect |
|----------|--------|
| `FEDORA_HARDENING_PROFILE` | `research` \| `desktop` \| `auto` — audit/hardening expectations |
| `FEDORA_HARDENING_FIREWALL_ZONE` | Override strict zone name (default `<hostname>-research`) |
| `FEDORA_HARDENING_LOG_ROOT` | Hardening baseline log root |
| `FEDORA_SECURITY_AUDIT_ROOT` | Audit report root |
| `NO_COLOR` / `FEDORA_NO_COLOR=1` | Plain text output |
| `FEDORA_THEME` | `dark` (default, black-terminal palette) or `light` |
| `FEDORA_THEME_WIDTH` | Rule/box width in columns (default `54`) |
| `FEDORA_THEME_DENSITY` | `normal` (default) or `compact` — tighter menus/sections |

Preview all elements: `./theme_preview.sh`

Lane picker items use `menu_item_lane` (accent `[n]` + lane icon). Round 2 / destructive
system menu entries use `menu_item_danger`. Tool/version rows use `theme_tool_row`.
Summary panels auto-color pass/fail via `theme_summary_box` (`Key: value` lines).

## Adding new smart checks

1. Add read-only probe to `users.sh`, `network.sh`, or `system_state.sh`.
2. Expose in `host_context_snapshot()` if useful for diff/compare.
3. Add finding + remediation in `lib/security_audit.sh` → `security_audit_analyze()`.
4. Keep `hardening_*` wrappers if legacy scripts still call them.
