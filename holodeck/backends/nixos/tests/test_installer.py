"""Tests for the optional NixOS system backend."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from subprocess import CompletedProcess
from unittest.mock import patch

import holodeck_system_nixos.installer as system_install
from holodeck.errors import HolodeckError
from holodeck_system_nixos.installer import (
    DiskCandidate,
    discover_desktop_disks,
    install_desktop,
    install_nixos,
    is_wsl_environment,
    parse_install_args,
    require_unmounted_disk,
    select_desktop_disk,
    validate_desktop_disk,
    validate_repo,
)


class ParseInstallArgsTests(unittest.TestCase):
    def test_desktop_detects_disk_when_override_is_omitted(self) -> None:
        request = parse_install_args(["--target", "desktop"])

        self.assertEqual(request.target, "desktop")
        self.assertIsNone(request.disk)

    def test_wsl_rejects_disk(self) -> None:
        with self.assertRaisesRegex(HolodeckError, "--disk no se acepta"):
            parse_install_args(
                [
                    "--target",
                    "wsl",
                    "--disk",
                    "/dev/disk/by-id/example",
                ]
            )

    def test_desktop_request_preserves_stable_disk_id(self) -> None:
        request = parse_install_args(
            [
                "--target",
                "desktop",
                "--disk",
                "/dev/disk/by-id/example",
                "--repo",
                ".",
            ]
        )

        self.assertEqual(request.target, "desktop")
        self.assertEqual(request.disk, "/dev/disk/by-id/example")
        self.assertTrue(request.repo.is_absolute())


class InstallDispatchTests(unittest.TestCase):
    def make_repo(self, root: Path, target: str) -> Path:
        (root / "flake.nix").write_text("{}\n")
        target_dir = root / "modules" / "hosts" / target
        target_dir.mkdir(parents=True)
        (target_dir / "default.nix").write_text("{}\n")
        return root

    def test_rejects_incomplete_repo(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            with self.assertRaisesRegex(HolodeckError, "repositorio completo"):
                validate_repo(Path(temp_dir), "wsl")

    def test_dispatches_wsl_without_user_setup(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo = self.make_repo(Path(temp_dir), "wsl")
            with patch.object(system_install, "install_wsl") as install_wsl:
                install_nixos(["--target", "wsl", "--repo", str(repo)])

            install_wsl.assert_called_once_with(repo.resolve())

    def test_dispatches_desktop_with_disk(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo = self.make_repo(Path(temp_dir), "desktop")
            disk = "/dev/disk/by-id/example"
            with patch.object(system_install, "install_desktop") as install_desktop:
                install_nixos(
                    [
                        "--target",
                        "desktop",
                        "--repo",
                        str(repo),
                        "--disk",
                        disk,
                    ]
                )

            install_desktop.assert_called_once_with(repo.resolve(), disk)

    def test_dispatches_desktop_without_disk_override(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo = self.make_repo(Path(temp_dir), "desktop")
            with patch.object(system_install, "install_desktop") as install_desktop:
                install_nixos(
                    [
                        "--target",
                        "desktop",
                        "--repo",
                        str(repo),
                    ]
                )

            install_desktop.assert_called_once_with(repo.resolve(), None)

    def test_rejects_unstable_desktop_device_name(self) -> None:
        with self.assertRaisesRegex(HolodeckError, "/dev/disk/by-id"):
            validate_desktop_disk("/dev/nvme0n1")


class DesktopDiskDiscoveryTests(unittest.TestCase):
    def candidate(self, stable_id: str, path: str) -> DiskCandidate:
        return DiskCandidate(
            stable_id=stable_id,
            resolved_path=Path(path),
            size_bytes=1_000_000_000,
            model="Test disk",
            serial="SERIAL",
            removable=False,
        )

    def test_ignores_mounted_disks_and_prefers_internal_disks(self) -> None:
        lsblk_output = {
            "blockdevices": [
                {
                    "path": "/dev/sda",
                    "type": "disk",
                    "rm": False,
                    "size": 1_000_000_000,
                    "model": "Internal",
                    "serial": "INTERNAL",
                    "mountpoints": [None],
                    "children": [],
                },
                {
                    "path": "/dev/sdb",
                    "type": "disk",
                    "rm": True,
                    "size": 2_000_000_000,
                    "model": "USB",
                    "serial": "USB",
                    "mountpoints": [None],
                    "children": [],
                },
                {
                    "path": "/dev/sdc",
                    "type": "disk",
                    "rm": False,
                    "size": 3_000_000_000,
                    "model": "Mounted",
                    "serial": "MOUNTED",
                    "mountpoints": [None],
                    "children": [
                        {
                            "path": "/dev/sdc1",
                            "type": "part",
                            "mountpoints": ["/run/media/live"],
                        }
                    ],
                },
            ]
        }
        completed = CompletedProcess(
            args=[],
            returncode=0,
            stdout=json.dumps(lsblk_output),
            stderr="",
        )

        with (
            patch.object(system_install.subprocess, "run", return_value=completed),
            patch.object(
                system_install,
                "stable_id_for_disk",
                side_effect=lambda path: f"/dev/disk/by-id/id-{path.name}",
            ),
        ):
            candidates = discover_desktop_disks()

        self.assertEqual(
            [candidate.stable_id for candidate in candidates],
            ["/dev/disk/by-id/id-sda"],
        )

    def test_automatically_uses_the_only_safe_candidate(self) -> None:
        candidate = self.candidate("/dev/disk/by-id/only", "/dev/sda")
        with patch.object(
            system_install,
            "discover_desktop_disks",
            return_value=[candidate],
        ):
            self.assertEqual(select_desktop_disk(), candidate.stable_id)

    def test_prompts_when_multiple_safe_candidates_exist(self) -> None:
        first = self.candidate("/dev/disk/by-id/first", "/dev/sda")
        second = self.candidate("/dev/disk/by-id/second", "/dev/sdb")
        with (
            patch.object(
                system_install,
                "discover_desktop_disks",
                return_value=[first, second],
            ),
            patch("builtins.input", return_value="2"),
        ):
            self.assertEqual(select_desktop_disk(), second.stable_id)

    def test_rejects_zero_as_a_disk_selection(self) -> None:
        first = self.candidate("/dev/disk/by-id/first", "/dev/sda")
        second = self.candidate("/dev/disk/by-id/second", "/dev/sdb")
        with (
            patch.object(
                system_install,
                "discover_desktop_disks",
                return_value=[first, second],
            ),
            patch("builtins.input", return_value="0"),
        ):
            with self.assertRaisesRegex(HolodeckError, "Seleccion de disco invalida"):
                select_desktop_disk()


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

    def test_disk_id_change_after_confirmation_aborts_before_disko(self) -> None:
        patches = self.desktop_patches()
        with (
            patches[0],
            patches[1],
            patch.object(
                system_install,
                "validate_desktop_disk",
                side_effect=[Path("/dev/first"), Path("/dev/changed")],
            ),
            patches[3],
            patches[4],
            patches[5],
            patches[6],
            patch("builtins.input", return_value=f"BORRAR {self.disk}"),
            patch.object(system_install, "run") as run_command,
        ):
            with self.assertRaisesRegex(HolodeckError, "ahora apunta a otro"):
                install_desktop(Path("/repo"), self.disk)

        self.assertFalse(
            any(call.args[0][0] == "sudo" for call in run_command.call_args_list)
        )


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
