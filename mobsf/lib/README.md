# MobSF shared library

MobSF-specific helpers live here (lane-local), separate from top-level `lib/`.

## Load in scripts

```bash
MOBSF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mobsf.sh
source "${MOBSF_DIR}/lib/mobsf.sh"
```

## Modules

| File | Responsibility |
|------|----------------|
| `mobsf.sh` | Loader — sources common + modules (entry point) |
| `config.sh` | URLs, bundle dir defaults |
| `paths.sh` | `~/MobSF/` paths, compose resolution, data dir prep |
| `podman.sh` | `mobsf_pc` / `mobsf_pd`, container discovery, HTTP check, status |
| `compose.sh` | Deploy Fedora bundle, validate guardrails |
| `stack.sh` | Install, reset, up/down, ordered startup |
| `menu.sh` | MobSF lane menus (sources `lib/menu.sh`) |
| `doctor.sh` | Readiness diagnostics + `mobsf_doctor_brief` |

## Backward compatibility

`lib/mobsf.sh` is a thin shim that re-sources this loader. Prefer `mobsf/lib/mobsf.sh` in new MobSF scripts.

## Related assets

- Compose bundle: `../compose/`
- CLI scripts: `../*.sh`
- Docs: `../README.md`, `../INSTALL.md`, etc.
