# ADR-0001: Project identity and workstation control model

- Status: Accepted
- Date: 2026-07-18
- Decision owners: Project maintainers

## Context

The repository began as `fedora-linux-scripts`, a collection of Fedora setup
and maintenance scripts. It now serves a broader role: it is the first
repository placed on a new Fedora workstation and coordinates bootstrap,
capability discovery, staged setup, verification, maintenance, diagnostics,
and recovery readiness.

Broad installers and host-specific assumptions make that role difficult to
operate safely across the older research laptop, the new Fedora 44
workstation, and future Fedora hosts. The project needs stable behavioral
contracts that separate observation from mutation and machine facts from
desired configuration.

## Decision

### Identity

The target project and repository name is:

```text
fedora-workstation-control
```

The project description is:

> Fedora research workstation bootstrap and lifecycle control plane.

The existing repository, remote, and entry points are not renamed by this
decision record. Renaming is a separate migration action after compatibility
and release details are planned.

### Mission

Provide a safe, declarative, and auditable control plane for bootstrapping,
configuring, validating, maintaining, and comparing Fedora research
workstations throughout their lifecycle.

The primary operating model is:

```text
Observed facts → Declared intent → Generated plan
```

- Observed facts are detected host state and are not committed by default.
- Declared intent is non-secret, validated configuration describing roles,
  capabilities, preferences, and service policy.
- A generated plan compares facts with intent, explains every proposed
  change, and cannot apply itself.

### Scope

The project owns:

- Fedora host inspection and capability discovery
- composable role and capability definitions
- deterministic change planning
- explicitly approved package installation and managed configuration
- independent service configure, initialize, enable, and start decisions
- verification, maintenance, diagnostics, security posture, and recovery
  readiness
- non-secret inventory export and host comparison for migration planning
- operator and maintainer documentation

The project does not own:

- database contents, replication, backup, or disaster recovery
- Mercury responsibilities
- project source repositories or copied Git working directories
- databases, datasets, APKs, PCAPs, ML models, or application data
- secrets or unencrypted credentials
- external backup payloads
- exact reproduction of a previous host

### Command contracts

The target command vocabulary is:

| Command | Contract |
|---------|----------|
| `status` | Fast live summary; no sudo, writes, repairs, or network-dependent mutation |
| `inspect` | Detailed read-only discovery; stdout by default; persists only with `--save` |
| `plan` | Compares observed facts with intent; reports actions and conflicts; cannot mutate |
| `apply` | Executes an explicit approved plan and records outcomes |
| `verify` | Checks declared intent and applied outcomes; never repairs |
| `repair` | Performs one explicitly named, narrowly scoped remediation |
| `snapshot` | Explicitly persists an inventory or health report |
| `diff` | Compares inventories, hosts, or observed state with intent |

Read-only commands must not:

- install packages or modify repositories
- start, stop, enable, disable, or initialize services
- edit configuration, groups, firewall rules, or security policy
- invoke automatic repairs
- write snapshots, logs, or caches in the Git worktree
- create or mount `/data`
- initialize MariaDB

### Configuration and capabilities

TOML is the target declarative configuration format. It is data rather than
executable shell code, supports typed validation, and is available through
Python's standard `tomllib` on supported hosts.

Roles are compositions of small capabilities. Examples include:

- `git`
- `compilers`
- `python-development`
- `podman`
- `kvm`
- `java-development`
- `android-platform-tools`
- `android-sdk-cli`
- `android-re-tools`
- `mariadb-client`
- `mariadb-server-packages`
- `mobsf`

Roles such as `developer`, `android-security`, `machine-learning`,
`database-host`, and `analysis-worker` select capabilities without hiding
their effects.

Service intent separates:

```text
package installed
configuration managed
service initialized
service enabled
service active
```

No step implies the next. In particular, installing MariaDB packages must not
initialize, enable, or start MariaDB.

### Runtime state

Machine-specific runtime artifacts move outside the Git worktree:

```text
~/.config/fedora-workstation-control/
~/.local/state/fedora-workstation-control/
~/.local/state/fedora-workstation-control/logs/
~/.cache/fedora-workstation-control/
```

The repository contains source, tests, documentation, schemas, templates, and
non-secret example or fleet intent. Inventories, plans, apply records, health
snapshots, and logs are runtime state. Secrets remain in a keyring, password
manager, or appropriately protected system configuration.

### Compatibility

Current entry points remain available temporarily as deprecated compatibility
wrappers. Existing scripts are classified and adapted behind the new command
contracts before removal. Host-specific behavior moves into declared intent
or compatibility layers rather than generic libraries.

Breaking CLI, configuration-schema, or state-layout changes require a major
release after the project reaches `1.0`.

## Consequences

Benefits:

- inspection and planning become safe on partially configured hosts
- capabilities can be reused across multiple Fedora machines
- optional components such as Docker, VirtualBox, MobSF, Android Studio, and
  `/data` no longer become implicit requirements
- migration is based on inventories and intent instead of cloning a machine
- plans and apply records provide an auditable explanation of changes

Costs:

- broad profiles and mixed-purpose scripts require gradual decomposition
- compatibility wrappers must be maintained during the transition
- a schema, planner, and state-location migration must be designed and tested
- current menus cannot become the source of truth for behavior

## First implementation milestone

Build a genuinely non-mutating `inspect` command and a versioned inventory
schema.

The command must:

- print to standard output by default
- save nothing unless `--save` is explicitly supplied
- work without sudo
- distinguish absent, optional, unavailable, and permission-limited facts
- avoid automatic repository refreshes or repairs
- include tool and inventory-schema versions

Menu redesign, broad installer rewrites, repository renaming, and declarative
`apply` behavior follow only after the inspection contract and schema are
stable.
