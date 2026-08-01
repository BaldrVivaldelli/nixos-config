"""Tests for the NixOS-WSL installation backend."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import holodeck_system_nixos.installer as system_install
from holodeck.errors import HolodeckError
from holodeck_system_nixos.installer import (
    install_nixos,
    is_wsl_environment,
    parse_install_args,
    validate_repo,
)


class ParseInstallArgsTests(unittest.TestCase):
    def test_accepts_wsl(self) -> None:
        request = parse_install_args(["--target", "wsl", "--repo", "."])

        self.assertEqual(request.target, "wsl")
        self.assertTrue(request.repo.is_absolute())

    def test_rejects_removed_desktop_target(self) -> None:
        with self.assertRaisesRegex(HolodeckError, "invalid choice"):
            parse_install_args(["--target", "desktop"])


class InstallDispatchTests(unittest.TestCase):
    @staticmethod
    def make_repo(root: Path) -> Path:
        (root / "flake.nix").touch()
        (root / "modules" / "hosts" / "wsl").mkdir(parents=True)
        (root / "modules" / "hosts" / "wsl" / "default.nix").touch()
        return root

    def test_rejects_incomplete_repo(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            with self.assertRaisesRegex(HolodeckError, "repositorio completo"):
                validate_repo(Path(temp_dir))

    def test_dispatches_wsl(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo = self.make_repo(Path(temp_dir))
            with patch.object(system_install, "install_wsl") as install_wsl:
                install_nixos(["--target", "wsl", "--repo", str(repo)])

            install_wsl.assert_called_once_with(repo.resolve())


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
