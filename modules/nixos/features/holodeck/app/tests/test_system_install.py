from __future__ import annotations

import tempfile
import unittest
from subprocess import CompletedProcess
from pathlib import Path
from unittest.mock import patch

import holodeck.system_install as system_install
from holodeck.errors import HolodeckError
from holodeck.system_install import (
    install_desktop,
    install_system,
    is_wsl_environment,
    parse_install_args,
    require_unmounted_disk,
    validate_desktop_disk,
    validate_repo,
)


class ParseInstallArgsTests(unittest.TestCase):
    def test_desktop_requires_disk(self) -> None:
        with self.assertRaisesRegex(HolodeckError, "--disk es obligatorio"):
            parse_install_args(["--host", "desktop"])

    def test_wsl_rejects_disk(self) -> None:
        with self.assertRaisesRegex(HolodeckError, "--disk no se acepta"):
            parse_install_args(
                [
                    "--host",
                    "wsl",
                    "--disk",
                    "/dev/disk/by-id/example",
                ]
            )

    def test_desktop_request_preserves_stable_disk_id(self) -> None:
        request = parse_install_args(
            [
                "--host",
                "desktop",
                "--disk",
                "/dev/disk/by-id/example",
                "--repo",
                ".",
            ]
        )

        self.assertEqual(request.host, "desktop")
        self.assertEqual(request.disk, "/dev/disk/by-id/example")
        self.assertTrue(request.repo.is_absolute())


class InstallDispatchTests(unittest.TestCase):
    def make_repo(self, root: Path, host: str) -> Path:
        (root / "flake.nix").write_text("{}\n")
        host_dir = root / "modules" / "hosts" / host
        host_dir.mkdir(parents=True)
        (host_dir / "default.nix").write_text("{}\n")
        return root

    def test_rejects_incomplete_repo(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            with self.assertRaisesRegex(HolodeckError, "repositorio completo"):
                validate_repo(Path(temp_dir), "wsl")

    def test_dispatches_wsl_without_user_setup(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo = self.make_repo(Path(temp_dir), "wsl")
            with patch("holodeck.system_install.install_wsl") as install_wsl:
                install_system(["--host", "wsl", "--repo", str(repo)])

            install_wsl.assert_called_once_with(repo.resolve())

    def test_dispatches_desktop_with_disk(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo = self.make_repo(Path(temp_dir), "desktop")
            disk = "/dev/disk/by-id/example"
            with patch("holodeck.system_install.install_desktop") as install_desktop:
                install_system(
                    [
                        "--host",
                        "desktop",
                        "--repo",
                        str(repo),
                        "--disk",
                        disk,
                    ]
                )

            install_desktop.assert_called_once_with(repo.resolve(), disk)

    def test_rejects_unstable_desktop_device_name(self) -> None:
        with self.assertRaisesRegex(HolodeckError, "/dev/disk/by-id"):
            validate_desktop_disk("/dev/nvme0n1")


class DesktopSafetyTests(unittest.TestCase):
    disk = "/dev/disk/by-id/example"
    resolved_disk = Path("/dev/mock-disk")

    def desktop_patches(self):
        return (
            patch.object(system_install, "require_commands"),
            patch.object(system_install.Path, "is_dir", return_value=True),
            patch.object(
                system_install,
                "validate_desktop_disk",
                return_value=self.resolved_disk,
            ),
            patch.object(system_install, "ensure_install_inputs_tracked"),
            patch.object(system_install, "check_flake"),
            patch.object(system_install, "require_mount"),
            patch.object(system_install, "require_vfat_boot"),
        )

    def test_wrong_confirmation_never_runs_sudo(self) -> None:
        patches = self.desktop_patches()
        with (
            patches[0],
            patches[1],
            patches[2],
            patches[3],
            patches[4],
            patches[5],
            patches[6],
            patch("builtins.input", return_value="no"),
            patch.object(system_install, "run") as run_command,
        ):
            with self.assertRaisesRegex(HolodeckError, "no se modifico"):
                install_desktop(Path("/repo"), self.disk)

        self.assertFalse(
            any(call.args[0][0] == "sudo" for call in run_command.call_args_list)
        )

    def test_mounted_disk_is_rejected(self) -> None:
        mounted = CompletedProcess(
            args=[],
            returncode=0,
            stdout="/mnt/old-root\n",
            stderr="",
        )
        with patch.object(system_install.subprocess, "run", return_value=mounted):
            with self.assertRaisesRegex(HolodeckError, "esta montada"):
                require_unmounted_disk(self.resolved_disk, self.disk)

    def test_confirmed_install_delegates_to_disko_and_nixos_install(self) -> None:
        patches = self.desktop_patches()
        with (
            patches[0],
            patches[1],
            patches[2],
            patches[3],
            patches[4],
            patches[5],
            patches[6],
            patch("builtins.input", return_value=f"BORRAR {self.disk}"),
            patch.object(system_install, "run") as run_command,
        ):
            install_desktop(Path("/repo"), self.disk)

        commands = [call.args[0] for call in run_command.call_args_list]
        self.assertEqual(commands[1][:3], ["sudo", "nix", "--extra-experimental-features"])
        self.assertIn("destroy,format,mount", commands[1])
        self.assertEqual(
            commands[2],
            ["sudo", "nixos-install", "--flake", ".#desktop"],
        )
        self.assertEqual(commands[3][0:2], ["sudo", "nixos-enter"])


class WslSafetyTests(unittest.TestCase):
    def test_wsl_environment_accepts_interop_marker(self) -> None:
        with (
            patch.dict(system_install.os.environ, {"WSL_INTEROP": "/run/WSL/1"}),
            patch.object(system_install.Path, "exists", return_value=False),
        ):
            self.assertTrue(is_wsl_environment())

    def test_non_wsl_environment_is_rejected(self) -> None:
        clean_environment = {
            key: value
            for key, value in system_install.os.environ.items()
            if key not in {"WSL_INTEROP", "WSL_DISTRO_NAME"}
        }
        with (
            patch.dict(system_install.os.environ, clean_environment, clear=True),
            patch.object(system_install.Path, "exists", return_value=False),
        ):
            self.assertFalse(is_wsl_environment())


if __name__ == "__main__":
    unittest.main()
