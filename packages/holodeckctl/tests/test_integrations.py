from __future__ import annotations

import io
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Any

from holodeckctl.errors import ConfigCtlError
from holodeckctl.integrations import (
    aws_profiles,
    execute_action,
    integration_status,
    provider_profiles,
)


class IntegrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.home = Path(self.temporary.name)
        self.bin = self.home / "bin"
        self.bin.mkdir()
        self.environment = {
            "HOME": str(self.home),
            "PATH": str(self.bin),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
        }

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def add_command(self, name: str) -> Path:
        command = self.bin / name
        command.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        command.chmod(0o755)
        return command

    def test_status_reports_only_non_secret_provider_metadata(self) -> None:
        profiles = self.home / ".config" / "holodeck" / "profiles"
        profiles.mkdir(parents=True)
        (profiles / "personal.env").write_text(
            "\n".join(
                (
                    "HOLODECK_PROFILE=personal",
                    "HOLODECK_PROVIDER=github",
                    "HOLODECK_HOST=github.com",
                    "HOLODECK_EMAIL=secret@example.com",
                    "HOLODECK_SSH_KEY=/secret/key",
                )
            ),
            encoding="utf-8",
        )
        for command in ("holodeck", "gh", "glab", "aws", "windowsvm"):
            self.add_command(command)

        status = integration_status(self.environment)

        self.assertTrue(status["github"]["configured"])
        self.assertEqual(
            [{"host": "github.com", "name": "personal", "provider": "github"}],
            status["github"]["profiles"],
        )
        self.assertNotIn("secret@example.com", repr(status))
        self.assertNotIn("/secret/key", repr(status))
        self.assertTrue(status["windowsVm"]["available"])

    def test_aws_profiles_reads_names_without_credentials(self) -> None:
        aws_dir = self.home / ".aws"
        aws_dir.mkdir()
        (aws_dir / "config").write_text(
            "[default]\nregion=us-east-1\n[profile work]\nsso_session=work\n",
            encoding="utf-8",
        )

        self.assertEqual(["default", "work"], aws_profiles(self.environment))

    def test_provider_profiles_ignores_unknown_providers(self) -> None:
        profiles = self.home / ".config" / "holodeck" / "profiles"
        profiles.mkdir(parents=True)
        (profiles / "other.env").write_text(
            "HOLODECK_PROFILE=other\nHOLODECK_PROVIDER=unknown\n",
            encoding="utf-8",
        )

        self.assertEqual([], provider_profiles(self.environment))

    def test_static_action_uses_resolved_argv_without_shell(self) -> None:
        executable = self.add_command("holodeck")
        calls: list[tuple[list[str], dict[str, Any]]] = []

        def runner(argv: list[str], **kwargs: Any) -> subprocess.CompletedProcess[str]:
            calls.append((argv, kwargs))
            return subprocess.CompletedProcess(argv, 0)

        result = execute_action(
            "github-setup",
            self.environment,
            runner=runner,
            stdout=io.StringIO(),
        )

        self.assertTrue(result["ok"])
        self.assertEqual([[str(executable), "github"]], [call[0] for call in calls])
        self.assertIs(calls[0][1]["shell"], False)

    def test_aws_action_selects_only_a_discovered_profile(self) -> None:
        executable = self.add_command("aws")
        aws_dir = self.home / ".aws"
        aws_dir.mkdir()
        (aws_dir / "config").write_text(
            "[profile personal]\nregion=us-east-1\n[profile work]\nregion=us-east-1\n",
            encoding="utf-8",
        )
        calls: list[list[str]] = []

        def runner(argv: list[str], **_kwargs: Any) -> subprocess.CompletedProcess[str]:
            calls.append(argv)
            return subprocess.CompletedProcess(argv, 0)

        execute_action(
            "aws-login",
            self.environment,
            runner=runner,
            input_fn=lambda _prompt: "2",
            stdout=io.StringIO(),
        )

        self.assertEqual(
            [[str(executable), "sso", "login", "--profile", "work"]], calls
        )

    def test_missing_action_dependency_is_rejected(self) -> None:
        with self.assertRaises(ConfigCtlError) as raised:
            execute_action(
                "windows-up",
                self.environment,
                stdout=io.StringIO(),
            )
        self.assertEqual("feature-unavailable", raised.exception.code)


if __name__ == "__main__":
    unittest.main()
