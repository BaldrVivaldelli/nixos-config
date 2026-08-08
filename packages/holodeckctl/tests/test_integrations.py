from __future__ import annotations

import hashlib
import io
import json
import subprocess
import tempfile
import time
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
            "XDG_RUNTIME_DIR": str(self.home / "runtime"),
        }
        Path(self.environment["XDG_RUNTIME_DIR"]).mkdir(mode=0o700)

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
        for command in ("holodeck", "gh", "aws", "windowsvm"):
            self.add_command(command)
        glab = self.add_command("glab")
        glab.write_text(
            "#!/bin/sh\n"
            "if [ \"$1 $2 $3\" = \"config get host\" ]; then\n"
            "  printf '%s\\n' gitlab.com\n"
            "fi\n"
            "exit 0\n",
            encoding="utf-8",
        )

        status = integration_status(self.environment)

        self.assertTrue(status["github"]["configured"])
        self.assertEqual(
            [{"host": "github.com", "name": "personal", "provider": "github"}],
            status["github"]["profiles"],
        )
        self.assertNotIn("secret@example.com", repr(status))
        self.assertNotIn("/secret/key", repr(status))
        self.assertTrue(status["gitlab"]["configured"])
        self.assertEqual(["gitlab.com"], status["gitlab"]["hosts"])
        self.assertEqual([], status["gitlab"]["profiles"])
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

    def test_gitlab_status_uses_glab_auth_not_a_legacy_profile(self) -> None:
        profiles = self.home / ".config" / "holodeck" / "profiles"
        profiles.mkdir(parents=True)
        (profiles / "legacy-gitlab.env").write_text(
            "HOLODECK_PROFILE=legacy-gitlab\n"
            "HOLODECK_PROVIDER=gitlab\n"
            "HOLODECK_HOST=gitlab.com\n",
            encoding="utf-8",
        )
        self.add_command("holodeck")
        glab = self.add_command("glab")
        glab.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")

        status = integration_status(self.environment)

        self.assertFalse(status["gitlab"]["configured"])
        self.assertEqual([], status["gitlab"]["hosts"])
        self.assertEqual([], status["gitlab"]["profiles"])

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

    def test_windows_rdp_receives_only_validated_display_mode(self) -> None:
        executable = self.add_command("windowsvm")
        calls: list[list[str]] = []

        def runner(argv: list[str], **_kwargs: Any) -> subprocess.CompletedProcess[str]:
            calls.append(argv)
            return subprocess.CompletedProcess(argv, 0)

        execute_action(
            "windows-rdp",
            self.environment,
            rdp_display_mode="fullscreen",
            runner=runner,
            stdout=io.StringIO(),
        )

        self.assertEqual([[str(executable), "rdp", "fullscreen"]], calls)

        with self.assertRaises(ConfigCtlError) as raised:
            execute_action(
                "windows-rdp",
                self.environment,
                rdp_display_mode="1920x1080",
                runner=runner,
                stdout=io.StringIO(),
            )
        self.assertEqual("invalid-rdp-display-mode", raised.exception.code)

    def test_windows_rdp_consumes_ephemeral_panel_credentials(self) -> None:
        executable = self.add_command("windowsvm")
        request = Path(self.environment["XDG_RUNTIME_DIR"]) / (
            "holodeck-control-windows-rdp.json"
        )
        request.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "createdAtMs": time.time_ns() // 1_000_000,
                    "username": "Docker",
                    "password": "runtime-only",
                }
            ),
            encoding="utf-8",
        )
        calls: list[tuple[list[str], dict[str, Any]]] = []

        def runner(
            argv: list[str], **kwargs: Any
        ) -> subprocess.CompletedProcess[str]:
            calls.append((argv, kwargs))
            return subprocess.CompletedProcess(argv, 0)

        result = execute_action(
            "windows-rdp",
            self.environment,
            rdp_display_mode="fullscreen",
            runner=runner,
            stdout=io.StringIO(),
        )

        self.assertTrue(result["ok"])
        self.assertFalse(request.exists())
        self.assertEqual(
            [str(executable), "rdp", "fullscreen"],
            calls[0][0],
        )
        self.assertEqual("Docker", calls[0][1]["env"]["WINDOWSVM_USER"])
        self.assertEqual(
            "runtime-only", calls[0][1]["env"]["WINDOWSVM_PASSWORD"]
        )
        self.assertNotIn("runtime-only", repr(result))

    def test_windows_password_reset_uses_only_ephemeral_panel_credentials(self) -> None:
        executable = self.add_command("windowsvm")
        request = Path(self.environment["XDG_RUNTIME_DIR"]) / (
            "holodeck-control-windows-rdp.json"
        )
        request.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "createdAtMs": time.time_ns() // 1_000_000,
                    "username": "Docker",
                    "password": "replacement-from-textbox",
                }
            ),
            encoding="utf-8",
        )
        calls: list[tuple[list[str], dict[str, Any]]] = []

        def runner(
            argv: list[str], **kwargs: Any
        ) -> subprocess.CompletedProcess[str]:
            calls.append((argv, kwargs))
            return subprocess.CompletedProcess(argv, 0)

        result = execute_action(
            "windows-password-reset",
            self.environment,
            runner=runner,
            stdout=io.StringIO(),
        )

        self.assertTrue(result["ok"])
        self.assertFalse(request.exists())
        self.assertEqual([str(executable), "password-reset"], calls[0][0])
        self.assertEqual("Docker", calls[0][1]["env"]["WINDOWSVM_USER"])
        self.assertEqual(
            "replacement-from-textbox",
            calls[0][1]["env"]["WINDOWSVM_PASSWORD"],
        )
        self.assertNotIn("replacement-from-textbox", repr(result))

    def test_windows_wipe_routes_textbox_credentials_with_explicit_confirmation(
        self,
    ) -> None:
        executable = self.add_command("windowsvm")
        request = Path(self.environment["XDG_RUNTIME_DIR"]) / (
            "holodeck-control-windows-rdp.json"
        )
        request.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "createdAtMs": time.time_ns() // 1_000_000,
                    "username": "Docker",
                    "password": "fresh-install-password",
                }
            ),
            encoding="utf-8",
        )
        calls: list[tuple[list[str], dict[str, Any]]] = []

        def runner(
            argv: list[str], **kwargs: Any
        ) -> subprocess.CompletedProcess[str]:
            calls.append((argv, kwargs))
            return subprocess.CompletedProcess(argv, 0)

        result = execute_action(
            "windows-wipe",
            self.environment,
            runner=runner,
            stdout=io.StringIO(),
        )

        self.assertTrue(result["ok"])
        self.assertFalse(request.exists())
        self.assertEqual([str(executable), "wipe"], calls[0][0])
        self.assertEqual("Docker", calls[0][1]["env"]["WINDOWSVM_USER"])
        self.assertEqual(
            "fresh-install-password",
            calls[0][1]["env"]["WINDOWSVM_PASSWORD"],
        )
        self.assertEqual("WIPE", calls[0][1]["env"]["WINDOWSVM_WIPE_CONFIRM"])
        self.assertNotIn("fresh-install-password", repr(result))

    def test_windows_rdp_rejects_and_removes_stale_panel_credentials(self) -> None:
        self.add_command("windowsvm")
        request = Path(self.environment["XDG_RUNTIME_DIR"]) / (
            "holodeck-control-windows-rdp.json"
        )
        request.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "createdAtMs": 0,
                    "username": "Docker",
                    "password": "stale-secret",
                }
            ),
            encoding="utf-8",
        )

        with self.assertRaises(ConfigCtlError) as raised:
            execute_action(
                "windows-rdp",
                self.environment,
                runner=lambda *_args, **_kwargs: self.fail("runner must not execute"),
                stdout=io.StringIO(),
            )

        self.assertEqual("invalid-rdp-request", raised.exception.code)
        self.assertFalse(request.exists())
        self.assertNotIn("stale-secret", str(raised.exception))

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

    def test_aws_sync_is_an_allowlisted_composite_action(self) -> None:
        executable = self.add_command("aws")
        self.environment.update(
            {
                "AWS_DEFAULT_REGION": "us-east-1",
            }
        )
        cache = self.home / ".aws" / "sso" / "cache"
        cache.mkdir(parents=True)
        key = hashlib.sha1(b"holodeck").hexdigest()
        (cache / f"{key}.json").write_text(
            json.dumps({"accessToken": "not-reported"}), encoding="utf-8"
        )

        class Paginator:
            def __init__(self, operation: str) -> None:
                self.operation = operation

            def paginate(self, **_kwargs: Any) -> list[dict[str, Any]]:
                if self.operation == "list_accounts":
                    return [
                        {
                            "accountList": [
                                {"accountId": "111111111111", "accountName": "Dev"}
                            ]
                        }
                    ]
                return [{"roleList": [{"roleName": "DeveloperAccess"}]}]

        class Client:
            def get_paginator(self, operation: str) -> Paginator:
                return Paginator(operation)

        calls: list[list[str]] = []

        def runner(argv: list[str], **_kwargs: Any) -> subprocess.CompletedProcess[str]:
            calls.append(argv)
            return subprocess.CompletedProcess(argv, 0)

        result = execute_action(
            "aws-sync",
            self.environment,
            runner=runner,
            input_fn=lambda prompt: (
                "https://example.awsapps.com/start" if "URL" in prompt else ""
            ),
            stdout=io.StringIO(),
            aws_client_factory=lambda _region: Client(),
        )

        self.assertTrue(result["ok"])
        self.assertEqual(1, result["assignmentCount"])
        self.assertEqual(0, result["pendingRegionCount"])
        self.assertEqual(2, result["profileCount"])
        self.assertEqual(str(executable), calls[0][0])
        status = integration_status(self.environment)
        self.assertEqual(1, len(status["aws"]["aliases"]))
        self.assertFalse(status["aws"]["aliases"][0]["pending"])
        self.assertEqual(0, status["aws"]["pendingRegionCount"])
        self.assertEqual("Dev", status["aws"]["aliases"][0]["accountName"])
        self.assertNotIn("111111111111", repr(status))
        self.assertNotIn("not-reported", repr(status))

    def test_holodeck_setup_offers_aws_and_runs_the_same_sync_flow(self) -> None:
        holodeck = self.add_command("holodeck")
        aws = self.add_command("aws")
        self.environment.update(
            {
                "AWS_DEFAULT_REGION": "us-east-1",
            }
        )
        cache = self.home / ".aws" / "sso" / "cache"
        cache.mkdir(parents=True)
        key = hashlib.sha1(b"holodeck").hexdigest()
        (cache / f"{key}.json").write_text(
            json.dumps({"accessToken": "not-reported"}), encoding="utf-8"
        )

        class Paginator:
            def __init__(self, operation: str) -> None:
                self.operation = operation

            def paginate(self, **_kwargs: Any) -> list[dict[str, Any]]:
                if self.operation == "list_accounts":
                    return [
                        {
                            "accountList": [
                                {"accountId": "111111111111", "accountName": "Dev"}
                            ]
                        }
                    ]
                return [{"roleList": [{"roleName": "DeveloperAccess"}]}]

        class Client:
            def get_paginator(self, operation: str) -> Paginator:
                return Paginator(operation)

        calls: list[list[str]] = []

        def runner(argv: list[str], **_kwargs: Any) -> subprocess.CompletedProcess[str]:
            calls.append(argv)
            return subprocess.CompletedProcess(argv, 0)

        result = execute_action(
            "holodeck-setup",
            self.environment,
            runner=runner,
            input_fn=lambda prompt: (
                "https://example.awsapps.com/start" if "URL" in prompt else ""
            ),
            stdout=io.StringIO(),
            aws_client_factory=lambda _region: Client(),
        )

        self.assertTrue(result["ok"])
        self.assertEqual(["git", "aws"], result["components"])
        self.assertEqual([str(holodeck), "setup"], calls[0])
        self.assertEqual(str(aws), calls[1][0])

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
