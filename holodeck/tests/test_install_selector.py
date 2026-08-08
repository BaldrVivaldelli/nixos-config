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
SOURCE_PREPARER = REPO / "prepare-flake-source.sh"
BASH = shutil.which("bash")


def write_echo_command(directory: Path, name: str) -> None:
    command = directory / name
    command.write_text(
        f"#!{sys.executable}\n"
        "import sys\n"
        'print(" ".join(sys.argv[1:]))\n'
    )
    command.chmod(0o755)


def write_fake_nix(directory: Path, store: Path) -> None:
    command = directory / "nix"
    command.write_text(
        f"#!{sys.executable}\n"
        "import os\n"
        "import sys\n"
        "from pathlib import Path\n"
        f"store = Path({str(store)!r})\n"
        "args = sys.argv[1:]\n"
        "if args[:2] == ['hash', 'path']:\n"
        "    print('sha256-test-snapshot')\n"
        "    sys.exit(0)\n"
        'print(" ".join(args))\n'
        "if 'build' in args and '--out-link' in args:\n"
        "    out_link = Path(args[args.index('--out-link') + 1])\n"
        "    is_system = any('nixosConfigurations.existing' in arg for arg in args)\n"
        "    candidate = store / ('nixos-candidate' if is_system else 'home-candidate')\n"
        "    candidate.mkdir(parents=True, exist_ok=True)\n"
        "    if is_system:\n"
        "        switcher = candidate / 'bin' / 'switch-to-configuration'\n"
        "        switcher.parent.mkdir(parents=True, exist_ok=True)\n"
        "        switcher.write_text('#!/bin/sh\\nexit 0\\n')\n"
        "        switcher.chmod(0o755)\n"
        "    else:\n"
        "        (candidate / 'gen-version').write_text('1\\n')\n"
        "        activate = candidate / 'activate'\n"
        "        activate.write_text('#!/bin/sh\\nprintf \\\"activate %s\\\\n\\\" \\\"$*\\\"\\n')\n"
        "        activate.chmod(0o755)\n"
        "    out_link.parent.mkdir(parents=True, exist_ok=True)\n"
        "    if out_link.is_symlink() or out_link.exists():\n"
        "        out_link.unlink()\n"
        "    os.symlink(candidate, out_link)\n"
    )
    command.chmod(0o755)


def write_fake_nix_env(directory: Path) -> None:
    command = directory / "nix-env"
    command.write_text(
        f"#!{sys.executable}\n"
        "import os\n"
        "import sys\n"
        "from pathlib import Path\n"
        "args = sys.argv[1:]\n"
        'print("nix-env " + " ".join(args))\n'
        "if '--profile' in args and '--set' in args:\n"
        "    profile = Path(args[args.index('--profile') + 1])\n"
        "    target = Path(args[args.index('--set') + 1])\n"
        "    profile.parent.mkdir(parents=True, exist_ok=True)\n"
        "    if profile.is_symlink() or profile.exists():\n"
        "        profile.unlink()\n"
        "    os.symlink(target, profile)\n"
    )
    command.chmod(0o755)


def write_fake_sudo(directory: Path) -> None:
    command = directory / "sudo"
    command.write_text(
        f"#!{sys.executable}\n"
        "import sys\n"
        "args = sys.argv[1:]\n"
        'print(" ".join(args))\n'
        "expected_config = 'NIX_CONFIG=experimental-features = nix-command flakes'\n"
        "valid_prefix = len(args) >= 3 and args[:3] == ['env', expected_config, 'nixos-rebuild']\n"
        "if not valid_prefix or '--no-reexec' not in args:\n"
        "    print('sudo call did not use the exact no-reexec path', file=sys.stderr)\n"
        "    sys.exit(64)\n"
    )
    command.chmod(0o755)


def make_home_generation(path: Path) -> None:
    path.mkdir(parents=True)
    (path / "gen-version").write_text("1\n")
    activate = path / "activate"
    activate.write_text("#!/bin/sh\nexit 0\n")
    activate.chmod(0o755)


def make_system_generation(path: Path) -> None:
    switcher = path / "bin" / "switch-to-configuration"
    switcher.parent.mkdir(parents=True)
    switcher.write_text("#!/bin/sh\nexit 0\n")
    switcher.chmod(0o755)


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
            store_root = command_dir / "store"
            store_root.mkdir()
            write_fake_nix(command_dir, store_root)
            write_fake_nix_env(command_dir)
            for command in extra_commands:
                if command == "sudo":
                    write_fake_sudo(command_dir)
                else:
                    write_echo_command(command_dir, command)
            system_root = command_dir / "system-root"
            (system_root / "etc" / "nixos").mkdir(parents=True)
            (system_root / "etc" / "NIXOS").touch()
            (system_root / "etc" / "nixos" / "configuration.nix").touch()
            previous_system = store_root / "nixos-previous"
            make_system_generation(previous_system)
            (system_root / "run").mkdir()
            os.symlink(previous_system, system_root / "run" / "current-system")
            previous_home = store_root / "home-previous"
            make_home_generation(previous_home)
            home_profiles = command_dir / "profiles"
            home_profiles.mkdir()
            os.symlink(previous_home, home_profiles / "home-manager")
            environment = os.environ.copy()
            environment["PATH"] = f"{command_dir}{os.pathsep}{environment['PATH']}"
            environment["NIXOS_CONFIG_SYSTEM_ROOT"] = str(system_root)
            environment["NIXOS_CONFIG_STATE_ROOT"] = str(command_dir / "state")
            environment["NIXOS_CONFIG_STORE_ROOT"] = str(store_root)
            environment["NIXOS_CONFIG_HM_PROFILE_DIR"] = str(home_profiles)
            inventory = command_dir / "inventory.local.nix"
            inventory.write_text("{}\n")
            environment["NIXOS_CONFIG_INVENTORY_PATH"] = str(inventory)
            if not (REPO / ".git").exists():
                environment["NIXOS_CONFIG_FLAKE_SOURCE"] = str(REPO)
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
        self.assertIn("#homeConfigurations.default.activationPackage", result.stdout)
        self.assertIn("nix-env --profile", result.stdout)
        self.assertIn("--set", result.stdout)
        self.assertIn("activate --driver-version 1", result.stdout)
        self.assertNotIn("\x1b", result.stderr)
        self.assertLess(
            result.stdout.index("#homeConfigurations.default.activationPackage"),
            result.stdout.index("nix-env --profile"),
        )

    def test_safe_source_contains_worktree_but_not_git_or_ignored_state(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            fixture = Path(temp_dir) / "repo"
            fixture.mkdir()
            shutil.copy2(SOURCE_PREPARER, fixture / SOURCE_PREPARER.name)
            (fixture / "flake.nix").write_text("{ description = \"tracked\"; }\n")
            (fixture / "deleted.nix").write_text("{}\n")
            (fixture / ".gitignore").write_text("*.cache\ninventory.local.nix\n")
            subprocess.run(["git", "init", "--quiet"], cwd=fixture, check=True)
            subprocess.run(["git", "add", "--all"], cwd=fixture, check=True)

            dirty_flake = '{ description = "dirty working tree"; }\n'
            (fixture / "flake.nix").write_text(dirty_flake)
            (fixture / "deleted.nix").unlink()
            (fixture / "inventory.local.nix").write_text("{}\n")
            (fixture / "private.cache").write_text("must stay out\n")

            result = subprocess.run(
                [BASH, str(fixture / SOURCE_PREPARER.name)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

            source = Path(result.stdout.strip())
            try:
                self.assertEqual((source / "flake.nix").read_text(), dirty_flake)
                self.assertFalse((source / ".git").exists())
                self.assertFalse((source / "private.cache").exists())
                self.assertFalse((source / "deleted.nix").exists())
                self.assertTrue((source / "inventory.local.nix").is_file())
            finally:
                shutil.rmtree(source)

    def test_noninteractive_apply_requires_local_inventory(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            isolated_installer = Path(temp_dir) / "install.sh"
            shutil.copy2(INSTALLER, isolated_installer)
            result = subprocess.run(
                [BASH, str(isolated_installer), "home-manager"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("falta inventory.local.nix", result.stderr)
        self.assertIn("./install.sh configure --yes", result.stderr)

    def test_recovery_restores_recorded_home_and_system_generations(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            command_dir = root / "bin"
            command_dir.mkdir()
            write_fake_nix_env(command_dir)
            write_fake_sudo(command_dir)
            write_echo_command(command_dir, "nixos-rebuild")

            store = root / "store"
            previous_home = store / "home-previous"
            candidate_home = store / "home-candidate"
            previous_system = store / "nixos-previous"
            candidate_system = store / "nixos-candidate"
            make_home_generation(previous_home)
            make_home_generation(candidate_home)
            make_system_generation(previous_system)
            make_system_generation(candidate_system)

            profiles = root / "profiles"
            profiles.mkdir()
            profile = profiles / "home-manager"
            os.symlink(candidate_home, profile)

            operation = root / "operation"
            operation.mkdir(mode=0o700)
            manifest = operation / "manifest"
            manifest.write_text(
                "version=1\n"
                "status=failed\n"
                "failure_phase=home-activation\n"
                "source_revision=test\n"
                f"system_previous={previous_system}\n"
                f"system_candidate={candidate_system}\n"
                f"home_profile={profile}\n"
                f"home_previous={previous_home}\n"
                f"home_candidate={candidate_home}\n"
            )
            manifest.chmod(0o600)

            environment = os.environ.copy()
            environment["PATH"] = f"{command_dir}{os.pathsep}{environment['PATH']}"
            environment["NIXOS_CONFIG_STORE_ROOT"] = str(store)
            result = subprocess.run(
                [BASH, str(INSTALLER), "recover", str(manifest)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
                env=environment,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(profile.resolve(), previous_home)
            self.assertIn("status=recovered", manifest.read_text())
            self.assertIn("nixos-rebuild switch --no-reexec --store-path", result.stdout)
            self.assertIn(
                "NIX_CONFIG=experimental-features = nix-command flakes",
                result.stdout,
            )
            self.assertLess(
                result.stdout.index("nix-env --profile"),
                result.stdout.index("nixos-rebuild switch --no-reexec --store-path"),
            )

    def test_regenerate_applies_home_manager_once_and_reloads_plugin(self) -> None:
        result = self.run_installer(
            ["regenerate"],
            extra_commands=("noctalia",),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count("#homeConfigurations.default.activationPackage"), 1)
        self.assertEqual(result.stdout.count("activate --driver-version 1"), 1)
        self.assertIn("msg plugins disable holodeck/control", result.stdout)
        self.assertIn("msg plugins enable holodeck/control", result.stdout)
        self.assertLess(
            result.stdout.index("activate --driver-version 1"),
            result.stdout.index("msg plugins disable holodeck/control"),
        )
        self.assertLess(
            result.stdout.index("msg plugins disable holodeck/control"),
            result.stdout.index("msg plugins enable holodeck/control"),
        )

    def test_nixos_home_manager_alias_uses_same_flow(self) -> None:
        result = self.run_installer(["nixos", "home-manager"])

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("#homeConfigurations.default.activationPackage", result.stdout)
        self.assertIn("activate --driver-version 1", result.stdout)

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
        self.assertIn("build --impure", result.stdout)
        self.assertIn("#nixosConfigurations.existing.config.system.build.toplevel", result.stdout)
        self.assertIn("nixos-rebuild switch --no-reexec --store-path", result.stdout)
        self.assertIn(
            "--option experimental-features nix-command flakes",
            result.stdout,
        )
        self.assertIn("--no-reexec", result.stdout)
        self.assertIn("#homeConfigurations.default.activationPackage", result.stdout)
        self.assertIn("activate --driver-version 1", result.stdout)
        self.assertLess(
            result.stdout.index("#nixosConfigurations.existing.config.system.build.toplevel"),
            result.stdout.index("#homeConfigurations.default.activationPackage"),
        )
        self.assertLess(
            result.stdout.index("#homeConfigurations.default.activationPackage"),
            result.stdout.index("nixos-rebuild switch --no-reexec --store-path"),
        )
        self.assertLess(
            result.stdout.index("nixos-rebuild switch --no-reexec --store-path"),
            result.stdout.index("activate --driver-version 1"),
        )
        source_references = {
            part.split("#", 1)[0]
            for part in result.stdout.split()
            if part.startswith("path:") and "#" in part
        }
        self.assertEqual(len(source_references), 1, result.stdout)

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
        self.assertIn("./install.sh regenerate", result.stdout)
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
