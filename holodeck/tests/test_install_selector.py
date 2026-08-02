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
CONFIGURATOR = REPO / "configure-inventory.sh"
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
        extra_environment: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess:
        if BASH is None:
            raise RuntimeError("bash is required to test install.sh")

        with tempfile.TemporaryDirectory() as temp_dir:
            command_dir = Path(temp_dir)
            write_echo_command(command_dir, "nix")
            for command in extra_commands:
                write_echo_command(command_dir, command)
            system_root = command_dir / "system-root"
            (system_root / "etc" / "nixos").mkdir(parents=True)
            (system_root / "etc" / "NIXOS").touch()
            (system_root / "etc" / "nixos" / "configuration.nix").touch()
            environment = os.environ.copy()
            environment["PATH"] = f"{command_dir}{os.pathsep}{environment['PATH']}"
            environment["NIXOS_CONFIG_SYSTEM_ROOT"] = str(system_root)
            environment.update(extra_environment or {})
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
        self.assertIn("run path:", result.stdout)
        self.assertIn("#holodeck-system-nixos", result.stdout)
        self.assertIn("--target wsl", result.stdout)

    def test_installs_home_manager_with_verify_build_and_switch(self) -> None:
        result = self.run_installer(["home-manager"])

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "OK: Home Manager no administra el sistema",
            result.stdout,
        )
        self.assertIn("-- build --flake", result.stdout)
        self.assertIn("-- switch -b hm-bak --flake", result.stdout)
        self.assertIn("#default", result.stdout)
        self.assertIn(
            "Nota: build no instala los programas.",
            result.stderr,
        )
        self.assertNotIn("\x1b", result.stderr)
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
        result = self.run_installer(
            [],
            input_text="1\n",
            extra_commands=("sudo", "nixos-rebuild"),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("nixos-rebuild build", result.stdout)
        self.assertIn("nixos-rebuild switch", result.stdout)
        self.assertIn("-- build --flake", result.stdout)
        self.assertIn("-- switch -b hm-bak --flake", result.stdout)
        self.assertLess(
            result.stdout.index("nixos-rebuild build"),
            result.stdout.index("-- build --flake"),
        )
        self.assertLess(
            result.stdout.index("-- build --flake"),
            result.stdout.index("nixos-rebuild switch"),
        )

    def test_interactive_selector_can_choose_wsl(self) -> None:
        result = self.run_installer([], input_text="2\n")

        self.assertEqual(result.returncode, 0)
        self.assertIn("--target wsl", result.stdout)

    def test_rejects_removed_desktop_target(self) -> None:
        result = self.run_installer(["nixos", "desktop"])

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("usá existing, home-manager o wsl", result.stderr)

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
        self.assertIn("#holodeck-system-macos", result.stdout)
        self.assertIn("install --repo", result.stdout)
        self.assertIn("--profile developer", result.stdout)

    def test_help_explains_machine_configuration(self) -> None:
        result = self.run_installer(["--help"])

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("./install.sh configure", result.stdout)
        self.assertIn("inventory.local.nix", result.stdout)

    def test_configure_print_uses_detected_overrides(self) -> None:
        result = self.run_installer(
            ["configure", "--print"],
            extra_environment={
                "NIXOS_CONFIG_USERNAME": "portable-user",
                "NIXOS_CONFIG_HOME": "/srv/portable-user",
                "NIXOS_CONFIG_REPO": str(REPO),
                "NIXOS_CONFIG_HOSTNAME": "portable-host",
                "NIXOS_CONFIG_SYSTEM": "aarch64-linux",
                "NIXOS_CONFIG_ARCHITECTURE": "aarch64",
                "NIXOS_CONFIG_TIME_ZONE": "Europe/Madrid",
                "NIXOS_CONFIG_OS": "nixos",
                "NIXOS_CONFIG_IS_WSL": "false",
            },
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('username = "portable-user";', result.stdout)
        self.assertIn('hostName = "portable-host";', result.stdout)
        self.assertIn('system = "aarch64-linux";', result.stdout)
        self.assertIn('timeZone = "Europe/Madrid";', result.stdout)
        self.assertIn("isWsl = false;", result.stdout)

    def test_configurator_does_not_overwrite_without_force(self) -> None:
        if BASH is None:
            raise RuntimeError("bash is required to test configure-inventory.sh")

        with tempfile.TemporaryDirectory() as temp_dir:
            output = Path(temp_dir) / "inventory.local.nix"
            environment = os.environ.copy()
            environment.update(
                {
                    "NIXOS_CONFIG_USERNAME": "portable-user",
                    "NIXOS_CONFIG_HOME": "/home/portable-user",
                    "NIXOS_CONFIG_REPO": str(REPO),
                    "NIXOS_CONFIG_HOSTNAME": "portable-host",
                    "NIXOS_CONFIG_IS_WSL": "false",
                }
            )
            command = [
                BASH,
                str(CONFIGURATOR),
                "--yes",
                "--output",
                str(output),
            ]

            first = subprocess.run(command, text=True, capture_output=True, env=environment)
            second = subprocess.run(command, text=True, capture_output=True, env=environment)

            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertTrue(output.exists())
            self.assertNotEqual(second.returncode, 0)
            self.assertIn("--force", second.stderr)


if __name__ == "__main__":
    unittest.main()
