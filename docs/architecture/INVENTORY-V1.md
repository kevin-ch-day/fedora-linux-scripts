# Inventory schema v1

`inspect.sh` is the first implementation of the workstation control model in
[ADR-0001](ADR-0001-project-identity-and-control-model.md).

## Contract

```bash
./inspect.sh
./inspect.sh --format text
./inspect.sh --save
./inspect.sh --save ~/inventory.json
./run.sh --inspect
```

Default behavior:

- prints inventory JSON to standard output
- does not invoke sudo
- does not query DNF repositories
- does not execute discovered third-party tools merely to obtain versions
- executes only a central allowlist of bounded, local, read-only probe commands
- does not install, configure, enable, start, stop, or repair anything
- does not write logs, snapshots, caches, or other repository files
- treats `/data` as an observed optional mount, not a requirement

`--save` is the only persistence path. Without an explicit path it writes:

```text
${XDG_STATE_HOME:-~/.local/state}/fedora-workstation-control/
  inventories/<hostname>/inventory_<timestamp>.json
```

Saved files and newly created directories use a restrictive process umask.
The JSON inventory is still printed to stdout; the saved path is printed to
stderr.

## Schema

The machine-readable schema is:

[schemas/inventory-v1.schema.json](../../schemas/inventory-v1.schema.json)

Schema version `1.0` contains:

- generator and schema versions
- host OS, kernel, and architecture
- CPU and memory facts
- desktop/session facts
- root, home, and optional `/data` mounts
- SELinux, Secure Boot, and firewalld state
- network radio and device state
- package, command, service, and data-directory capability facts
- explicit inspection limitations

Observed state is not declared intent. For example:

- `docker.command.available=false` means Docker was not observed; it does not
  declare that Docker must remain absent.
- `storage.data.mounted=false` is informational and is not a health failure.
- MariaDB package, data-directory, enabled, and active states are independent.
- `mariadb.data_directory.initialized=null` means initialization could not be
  determined without additional access; the inspector does not escalate.

## Stability

Within inventory schema v1:

- required top-level keys remain stable
- new capability objects may be added
- capability details may be extended compatibly
- breaking field changes require a new schema file and schema version

Inventory files contain host-specific runtime facts and should not be
committed by default.
