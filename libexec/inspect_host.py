#!/usr/bin/env python3
"""Non-mutating Fedora host inventory.

Default behavior writes JSON to stdout only. Persistent output is opt-in via
--save and goes to the XDG state directory unless a path is supplied.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import platform
import shlex
import shutil
import socket
import subprocess
import sys
from pathlib import Path
from typing import Any, Sequence


PROJECT_NAME = "fedora-workstation-control"
TOOL_VERSION = "0.1.0"
SCHEMA_VERSION = "1.0"
SAFE_PROBE_COMMANDS = frozenset(
    {
        "firewall-cmd",
        "findmnt",
        "getenforce",
        "mokutil",
        "nmcli",
        "rpm",
        "systemctl",
    }
)


def read_text(path: str | Path) -> str:
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace").strip()
    except (OSError, PermissionError):
        return ""


def run_local(args: Sequence[str], timeout: float = 4.0) -> tuple[int, str]:
    """Run a bounded local read-only probe without a shell."""
    if not args:
        return 127, ""
    if args[0] not in SAFE_PROBE_COMMANDS:
        return 126, ""
    if shutil.which(args[0]) is None:
        return 127, ""
    env = os.environ.copy()
    env.update({"LC_ALL": "C", "LANG": "C"})
    try:
        proc = subprocess.run(
            list(args),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
            check=False,
            env=env,
        )
    except (OSError, subprocess.TimeoutExpired):
        return 124, ""
    return proc.returncode, proc.stdout.strip()


def first_line(value: str) -> str:
    return value.splitlines()[0].strip() if value else ""


def parse_os_release() -> dict[str, str]:
    values: dict[str, str] = {}
    for line in read_text("/etc/os-release").splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, raw = line.split("=", 1)
        try:
            parsed = shlex.split(raw)
            values[key] = parsed[0] if parsed else ""
        except ValueError:
            values[key] = raw.strip("\"'")
    return {
        "id": values.get("ID", "unknown"),
        "version_id": values.get("VERSION_ID", "unknown"),
        "pretty_name": values.get("PRETTY_NAME", "unknown"),
    }


def command_fact(name: str) -> dict[str, Any]:
    """Report command resolution without executing the discovered program."""
    path = shutil.which(name)
    return {"available": path is not None, "path": path}


def rpm_installed(name: str) -> bool:
    rc, _ = run_local(["rpm", "-q", name])
    return rc == 0


def rpm_provider(path: str | None) -> str | None:
    if not path:
        return None
    try:
        resolved = str(Path(path).resolve())
    except OSError:
        resolved = path
    rc, output = run_local(["rpm", "-qf", resolved])
    return first_line(output) if rc == 0 else None


def package_command_fact(
    packages: str | Sequence[str],
    command: str,
) -> dict[str, Any]:
    package_names = [packages] if isinstance(packages, str) else list(packages)
    cmd = command_fact(command)
    return {
        "packages": {name: rpm_installed(name) for name in package_names},
        "command": cmd,
        "provider": rpm_provider(cmd.get("path")),
    }


def service_fact(unit: str) -> dict[str, str]:
    _, enabled = run_local(["systemctl", "is-enabled", unit])
    _, active = run_local(["systemctl", "is-active", unit])
    return {
        "unit": unit,
        "enabled": first_line(enabled) or "unknown",
        "active": first_line(active) or "unknown",
    }


def mount_fact(target: str) -> dict[str, Any]:
    rc, output = run_local(
        ["findmnt", "--json", "--target", target, "--output", "SOURCE,FSTYPE,OPTIONS"]
    )
    if rc != 0 or not output:
        return {
            "target": target,
            "mounted": False,
            "source": None,
            "fstype": None,
            "options": [],
        }
    try:
        filesystems = json.loads(output).get("filesystems", [])
        entry = filesystems[0] if filesystems else {}
    except (json.JSONDecodeError, IndexError, TypeError):
        entry = {}
    options = entry.get("options") or ""
    return {
        "target": target,
        "mounted": bool(entry),
        "source": entry.get("source"),
        "fstype": entry.get("fstype"),
        "options": [item for item in options.split(",") if item],
    }


def cpu_model() -> str:
    for line in read_text("/proc/cpuinfo").splitlines():
        if line.lower().startswith("model name") and ":" in line:
            return line.split(":", 1)[1].strip()
    return platform.processor() or "unknown"


def memory_total_bytes() -> int | None:
    for line in read_text("/proc/meminfo").splitlines():
        if line.startswith("MemTotal:"):
            fields = line.split()
            if len(fields) >= 2 and fields[1].isdigit():
                return int(fields[1]) * 1024
    return None


def secure_boot_state() -> str:
    rc, output = run_local(["mokutil", "--sb-state"])
    lowered = output.lower()
    if "enabled" in lowered:
        return "enabled"
    if "disabled" in lowered:
        return "disabled"
    return "unknown" if rc != 0 else first_line(output) or "unknown"


def selinux_state() -> str:
    _, output = run_local(["getenforce"])
    return first_line(output).lower() or "unknown"


def firewalld_state() -> str:
    rc, output = run_local(["firewall-cmd", "--state"])
    return first_line(output) if rc == 0 else "unavailable"


def network_facts() -> dict[str, Any]:
    _, wifi = run_local(["nmcli", "-t", "-f", "WIFI", "general"])
    _, devices = run_local(["nmcli", "-t", "-f", "TYPE,STATE", "device", "status"])
    device_lines = [line for line in devices.splitlines() if line]
    return {
        "wifi_radio": first_line(wifi) or "unknown",
        "wired_connected": any(
            line.startswith("ethernet:") and "connected" in line for line in device_lines
        ),
        "device_states": device_lines,
    }


def directory_state(path: str) -> dict[str, Any]:
    target = Path(path).expanduser()
    exists = target.exists()
    return {
        "path": str(target),
        "exists": exists,
        "readable": os.access(target, os.R_OK) if exists else False,
    }


def mariadb_initialization_state() -> dict[str, Any]:
    data_dir = Path("/var/lib/mysql")
    state: dict[str, Any] = {
        "path": str(data_dir),
        "exists": data_dir.exists(),
        "readable": False,
        "initialized": None,
    }
    if not data_dir.exists():
        state["initialized"] = False
        return state
    if not os.access(data_dir, os.R_OK | os.X_OK):
        return state
    state["readable"] = True
    try:
        names = {entry.name for entry in data_dir.iterdir()}
    except OSError:
        return state
    markers = {"mysql", "ibdata1", "aria_log_control"}
    state["initialized"] = bool(names & markers)
    return state


def android_studio_state() -> dict[str, Any]:
    home = Path.home()
    candidates = [
        home / ".local/share/flatpak/app/com.google.AndroidStudio",
        Path("/var/lib/flatpak/app/com.google.AndroidStudio"),
    ]
    present = next((str(path) for path in candidates if path.exists()), None)
    return {"installed": present is not None, "detected_path": present}


def collect_inventory() -> dict[str, Any]:
    root_mount = mount_fact("/")
    home_mount = mount_fact("/home")
    data_mount = mount_fact("/data")
    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)

    java = package_command_fact(
        ["java-25-openjdk", "java-25-openjdk-headless", "java-21-openjdk"],
        "java",
    )
    java["compiler"] = command_fact("javac")

    return {
        "schema_version": SCHEMA_VERSION,
        "generated_at": now.isoformat().replace("+00:00", "Z"),
        "generator": {"name": PROJECT_NAME, "version": TOOL_VERSION},
        "host": {
            "hostname": socket.gethostname(),
            "os": parse_os_release(),
            "kernel": platform.release(),
            "architecture": platform.machine(),
        },
        "hardware": {
            "cpu_model": cpu_model(),
            "logical_cpus": os.cpu_count(),
            "memory_total_bytes": memory_total_bytes(),
        },
        "session": {
            "desktop": os.environ.get("XDG_CURRENT_DESKTOP") or None,
            "type": os.environ.get("XDG_SESSION_TYPE") or None,
        },
        "storage": {
            "root": root_mount,
            "home": home_mount,
            "data": data_mount,
            "root_encrypted": bool(
                root_mount.get("source")
                and str(root_mount["source"]).startswith("/dev/mapper/")
            ),
        },
        "security": {
            "selinux": selinux_state(),
            "secure_boot": secure_boot_state(),
            "firewalld": firewalld_state(),
        },
        "network": network_facts(),
        "capabilities": {
            "git": package_command_fact("git", "git"),
            "github_cli": package_command_fact("gh", "gh"),
            "vscode": package_command_fact("code", "code"),
            "cursor": package_command_fact("cursor", "cursor"),
            "podman": package_command_fact("podman", "podman"),
            "docker": package_command_fact(
                ["docker", "moby-engine", "docker-ce"], "docker"
            ),
            "kvm": package_command_fact("qemu-kvm", "qemu-system-x86_64"),
            "libvirt": {
                **package_command_fact("libvirt-daemon", "virsh"),
                "services": [
                    service_fact("libvirtd.service"),
                    service_fact("virtqemud.service"),
                ],
            },
            "virtualbox": package_command_fact(
                ["VirtualBox", "akmod-VirtualBox"], "VBoxManage"
            ),
            "java": java,
            "android_platform_tools": package_command_fact("android-tools", "adb"),
            "android_sdk": {
                "directory": directory_state("~/Android/Sdk"),
                "sdkmanager": command_fact("sdkmanager"),
            },
            "android_studio": android_studio_state(),
            "wireshark": package_command_fact("wireshark", "wireshark"),
            "mariadb": {
                "packages": {
                    name: rpm_installed(name)
                    for name in ("mariadb", "mariadb-server", "mariadb-backup")
                },
                "client": command_fact("mariadb"),
                "service": service_fact("mariadb.service"),
                "data_directory": mariadb_initialization_state(),
            },
            "apache": {
                **package_command_fact("httpd", "httpd"),
                "service": service_fact("httpd.service"),
            },
        },
        "limitations": [
            "Package state is read from the local RPM database; repository availability is not inspected.",
            "Only centrally allowlisted local read-only probe commands may execute.",
            "Privileged configuration contents are not inspected without access.",
            "MariaDB initialization is null when its data directory cannot be read.",
        ],
    }


def render_text(inventory: dict[str, Any]) -> str:
    host = inventory["host"]
    storage = inventory["storage"]
    security = inventory["security"]
    capabilities = inventory["capabilities"]
    mariadb = capabilities["mariadb"]

    def yes_no(value: bool) -> str:
        return "yes" if value else "no"

    lines = [
        "Fedora workstation inspection",
        f"Schema: {inventory['schema_version']}  Generated: {inventory['generated_at']}",
        "",
        f"Host: {host['hostname']}",
        f"OS: {host['os']['pretty_name']}",
        f"Kernel: {host['kernel']} ({host['architecture']})",
        f"Desktop: {inventory['session']['desktop'] or 'unknown'}",
        "",
        f"Root: {storage['root']['fstype'] or 'unknown'}"
        f" on {storage['root']['source'] or 'unknown'}",
        f"Root encrypted: {yes_no(storage['root_encrypted'])}",
        f"/data mounted: {yes_no(storage['data']['mounted'])} (optional)",
        "",
        f"SELinux: {security['selinux']}",
        f"Secure Boot: {security['secure_boot']}",
        f"firewalld: {security['firewalld']}",
        "",
        f"Podman: {yes_no(capabilities['podman']['command']['available'])}",
        f"Docker: {yes_no(capabilities['docker']['command']['available'])}",
        f"KVM/QEMU: {yes_no(capabilities['kvm']['command']['available'])}",
        f"VirtualBox: {yes_no(capabilities['virtualbox']['command']['available'])}",
        f"Java runtime: {yes_no(capabilities['java']['command']['available'])}",
        f"Java compiler: {yes_no(capabilities['java']['compiler']['available'])}",
        f"ADB: {yes_no(capabilities['android_platform_tools']['command']['available'])}",
        f"Android SDK: {yes_no(capabilities['android_sdk']['directory']['exists'])}",
        "",
        "MariaDB:",
        f"  server package: {yes_no(mariadb['packages']['mariadb-server'])}",
        f"  initialized: {mariadb['data_directory']['initialized']}",
        f"  enabled: {mariadb['service']['enabled']}",
        f"  active: {mariadb['service']['active']}",
    ]
    return "\n".join(lines)


def default_state_root() -> Path:
    configured = os.environ.get("XDG_STATE_HOME")
    if configured:
        return Path(configured).expanduser() / PROJECT_NAME
    return Path.home() / ".local" / "state" / PROJECT_NAME


def save_inventory(inventory: dict[str, Any], destination: str) -> Path:
    if destination == "auto":
        stamp = inventory["generated_at"].replace("-", "").replace(":", "")
        stamp = stamp.replace("T", "_").removesuffix("Z")
        host = inventory["host"]["hostname"].replace("/", "_")
        path = default_state_root() / "inventories" / host / f"inventory_{stamp}.json"
    else:
        path = Path(destination).expanduser()
        if path.exists() and path.is_dir():
            path = path / "inventory.json"

    old_umask = os.umask(0o077)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_name(f".{path.name}.tmp")
        temporary.write_text(
            json.dumps(inventory, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        temporary.replace(path)
    finally:
        os.umask(old_umask)
    return path


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Inspect local Fedora host state without sudo, package repository "
            "refreshes, repairs, or implicit file writes."
        )
    )
    parser.add_argument(
        "--format",
        choices=("json", "text"),
        default="json",
        help="stdout format (default: json)",
    )
    parser.add_argument(
        "--save",
        nargs="?",
        const="auto",
        metavar="PATH",
        help=(
            "persist JSON inventory; default destination is the XDG state "
            "directory"
        ),
    )
    parser.add_argument(
        "--schema-version",
        action="store_true",
        help="print the inventory schema version and exit",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    if args.schema_version:
        print(SCHEMA_VERSION)
        return 0

    inventory = collect_inventory()
    saved_path = save_inventory(inventory, args.save) if args.save else None

    if args.format == "text":
        print(render_text(inventory))
    else:
        print(json.dumps(inventory, indent=2, sort_keys=True))
    if saved_path:
        print(f"saved: {saved_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
