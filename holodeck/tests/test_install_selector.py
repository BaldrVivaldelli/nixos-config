"""Smoke tests for the single installation entrypoint."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
INSTALLER = REPO / "install.sh"


def write_echo_command(directory: Path, name: str) -> None:
    command = directory / name
    command.write_text('#!/bin/sh\nprintf "%s\\n" "$*"\n')
    command.chmod(0o755)


class InstallSelectorTests(unittest.TestCase):
    def run_installer(
        self,
        args: list[str],
        *,
        input_text: str | None = None,
        extra_commands: tuple[str, ...] = (),
    ) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as temp_dir:
            command_dir = Path(temp_dir)
            write_echo_command(command_dir, "nix")
            for command in extra_commands:
                write_echo_command(command_dir, command)
            environment = os.environ.copy()
            environment["PATH"] = f"{command_dir}{os.pathsep}{environment['PATH']}"
            return subprocess.run(
                [str(INSTALLER), *args],
                input=input_text,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
                env=environment,
            )

    def test_routes_nixos_desktop_to_optional_backend(self) -> None:
        result = self.run_installer(["nixos", "desktop"])

        self.assertEqual(result.returncode, 0)
        self.assertIn("run .#holodeck-system-nixos", result.stdout)
        self.assertIn("--target desktop", result.stdout)
        self.assertNotIn("--disk", result.stdout)

    def test_desktop_accepts_an_explicit_disk_override(self) -> None:
        result = self.run_installer(
            [
                "nixos",
                "desktop",
                "--disk",
                "/dev/disk/by-id/example",
            ]
        )

        self.assertEqual(result.returncode, 0)
        self.assertIn("--disk /dev/disk/by-id/example", result.stdout)

    def test_routes_nixos_wsl_to_optional_backend(self) -> None:
        result = self.run_installer(["nixos", "wsl"])

        self.assertEqual(result.returncode, 0)
        self.assertIn("--target wsl", result.stdout)
        self.assertNotIn("--disk", result.stdout)

    def test_interactive_selector_can_choose_wsl(self) -> None:
        result = self.run_installer([], input_text="1\n2\n")

        self.assertEqual(result.returncode, 0)
        self.assertIn("--target wsl", result.stdout)

    def test_interactive_selector_can_choose_desktop_without_disk_prompt(self) -> None:
        result = self.run_installer([], input_text="1\n1\n")

        self.assertEqual(result.returncode, 0)
        self.assertIn("--target desktop", result.stdout)
        self.assertNotIn("--disk", result.stdout)

    def test_routes_external_backend_by_executable_contract(self) -> None:
        result = self.run_installer(
            ["ubuntu", "--channel", "stable"],
            extra_commands=("holodeck-system-ubuntu",),
        )

        self.assertEqual(result.returncode, 0)
        self.assertIn("install --repo", result.stdout)
        self.assertIn("--channel stable", result.stdout)

    def test_routes_repo_backend_by_flake_app_contract(self) -> None:
        result = self.run_installer(["macos", "--profile", "developer"])

        self.assertEqual(result.returncode, 0)
        self.assertIn("run .#holodeck-system-macos", result.stdout)
        self.assertIn("install --repo", result.stdout)
        self.assertIn("--profile developer", result.stdout)


if __name__ == "__main__":
    unittest.main()
