#!/usr/bin/env python3
"""Regression tests for the non-mutating host inspector."""

from __future__ import annotations

import json
import importlib.util
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INSPECT = ROOT / "inspect.sh"
SCHEMA = ROOT / "schemas" / "inventory-v1.schema.json"


class InspectTests(unittest.TestCase):
    def run_inspect(
        self, state_home: Path, *args: str
    ) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        sandbox = state_home.parent
        env["HOME"] = str(sandbox / "home")
        env["XDG_STATE_HOME"] = str(state_home)
        env["XDG_CONFIG_HOME"] = str(sandbox / "config")
        env["XDG_CACHE_HOME"] = str(sandbox / "cache")
        env["XDG_DATA_HOME"] = str(sandbox / "data")
        return subprocess.run(
            ["bash", str(INSPECT), *args],
            cwd=ROOT,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
            check=False,
        )

    def test_default_is_json_and_does_not_create_state(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_home = Path(tmp) / "state"
            result = self.run_inspect(state_home)
            self.assertEqual(result.returncode, 0, result.stderr)
            inventory = json.loads(result.stdout)
            self.assertEqual(inventory["schema_version"], "1.0")
            self.assertEqual(
                inventory["generator"]["name"], "fedora-workstation-control"
            )
            self.assertIn("mariadb", inventory["capabilities"])
            self.assertIn("mounted", inventory["storage"]["data"])
            self.assertFalse(state_home.exists())
            self.assertFalse((Path(tmp) / "home").exists())
            self.assertFalse((Path(tmp) / "config").exists())
            self.assertFalse((Path(tmp) / "cache").exists())
            self.assertFalse((Path(tmp) / "data").exists())

    def test_save_is_explicit_and_uses_state_home(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_home = Path(tmp) / "state"
            result = self.run_inspect(state_home, "--save")
            self.assertEqual(result.returncode, 0, result.stderr)
            json.loads(result.stdout)
            saved = list(state_home.rglob("inventory_*.json"))
            self.assertEqual(len(saved), 1)
            self.assertIn("saved:", result.stderr)
            self.assertEqual(json.loads(saved[0].read_text())["schema_version"], "1.0")
            self.assertEqual(saved[0].stat().st_mode & 0o777, 0o600)
            self.assertEqual(saved[0].parent.stat().st_mode & 0o777, 0o700)

    def test_text_output_identifies_optional_data_mount(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = self.run_inspect(Path(tmp) / "state", "--format", "text")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("/data mounted:", result.stdout)
            self.assertIn("(optional)", result.stdout)

    def test_schema_file_is_valid_json(self) -> None:
        schema = json.loads(SCHEMA.read_text())
        self.assertEqual(schema["properties"]["schema_version"]["const"], "1.0")
        self.assertFalse(schema["additionalProperties"])

    def test_probe_allowlist_rejects_mutating_or_application_commands(self) -> None:
        module_path = ROOT / "libexec" / "inspect_host.py"
        spec = importlib.util.spec_from_file_location("inspect_host", module_path)
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        for command in ("dnf", "sudo", "gh", "podman", "flatpak"):
            rc, output = module.run_local([command, "--version"])
            self.assertEqual(rc, 126)
            self.assertEqual(output, "")


if __name__ == "__main__":
    unittest.main()
