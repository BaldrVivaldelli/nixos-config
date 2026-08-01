"""Smoke tests for the portable installation selector."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
INSTALLER = REPO / "install.sh"
BASH = shutil.which("bash")


def write_echo_command(directory: Path, name: str) -> None:
    command = directory / name
    command.write_text(
        f"#!{sys.executable}\n"
        "import sys\n"
        'print(" ".join(sys.argv[1:]))\n'
    )
    command.chmod(0o755)


class InstallSelectorTests(unittest.TestCase):
    def run_installer(
        self,
        args: list[str],
        *,
        input_text: str | None = None,
        extra_commands: tuple[str, ...] = (),
    ) -> subprocess.CompletedProcess:
        if BASH is None:
            raise RuntimeError("bash is required to test install.sh")

        with tempfile.TemporaryDirectory() as temp_dir:
            command_dir = Path(temp_dir)
            write_echo_command(command_dir, "nix")
            for command in extra_commands:
                write_echo_command(command_dir, command)
            environment = os.environ.copy()
            environment["PATH"] = f"{command_dir}{os.pathsep}{environment['PATH']}"
            return subprocess.run(
                [BASH, str(INSTALLER), *args],
                input=input_text,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
                env=environment,
            )

    def test_routes_explicit_nixos_wsl(self) -> None:
        result = self.run_installer(["nixos", "wsl"])

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("run .#holodeck-system-nixos", result.stdout)
        self.assertIn("--target wsl", result.stdout)

    def test_installs_home_manager_with_verify_build_and_switch(self) -> None:
        result = self.run_installer(["home-manager"])

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "OK: la configuración standalone de Home Manager",
            result.stdout,
        )
        self.assertIn("-- build --flake", result.stdout)
        self.assertIn("-- switch -b hm-bak --flake", result.stdout)
        self.assertLess(
            result.stdout.index("-- build --flake"),
            result.stdout.index("-- switch -b hm-bak --flake"),
        )

    def test_nixos_home_manager_alias_uses_same_flow(self) -> None:
        result = self.run_installer(["nixos", "home-manager"])

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-- build --flake", result.stdout)
        self.assertIn("-- switch -b hm-bak --flake", result.stdout)

    def test_nixos_defaults_to_wsl(self) -> None:
        result = self.run_installer(["nixos"])

        self.assertEqual(result.returncode, 0)
        self.assertIn("--target wsl", result.stdout)

    def test_interactive_selector_can_choose_home_manager(self) -> None:
        result = self.run_installer([], input_text="1\n")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-- build --flake", result.stdout)
        self.assertIn("-- switch -b hm-bak --flake", result.stdout)

    def test_interactive_selector_can_choose_wsl(self) -> None:
        result = self.run_installer([], input_text="2\n")

        self.assertEqual(result.returncode, 0)
        self.assertIn("--target wsl", result.stdout)

    def test_rejects_removed_desktop_target(self) -> None:
        result = self.run_installer(["nixos", "desktop"])

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("usá home-manager o wsl", result.stderr)

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
