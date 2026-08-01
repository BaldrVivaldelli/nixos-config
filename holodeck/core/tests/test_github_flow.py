"""Regression tests for the GitHub/SSH Holodeck workflow."""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from holodeck.errors import HolodeckError
from holodeck.keys import ensure_gpg_key, write_git_profile
from holodeck.providers import login_github, upload_github_ssh_key
from holodeck.workflows import _ssh_test


class GithubFlowTests(unittest.TestCase):
    def test_login_skips_gh_key_selection_and_requests_key_scopes(self) -> None:
        with (
            patch("holodeck.providers.command_ok", return_value=False),
            patch("holodeck.providers.run") as runner,
        ):
            login_github("github.com")

        login_args = runner.call_args_list[0].args[0]
        self.assertIn("--skip-ssh-key", login_args)
        self.assertIn("write:public_key,read:public_key", login_args)
        self.assertEqual(
            runner.call_args_list[1].args[0],
            ["gh", "config", "set", "git_protocol", "ssh", "--host", "github.com"],
        )

    def test_gpg_off_never_calls_gpg(self) -> None:
        with patch("holodeck.keys.subprocess.run") as process:
            self.assertEqual(ensure_gpg_key("Name", "mail@example.com", "off"), "")
        process.assert_not_called()

    def test_git_profile_uses_exact_ssh_key_and_rewrites_https(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "profile.gitconfig"
            key = Path(directory) / "holodeck_key"
            with patch("holodeck.keys.git_profile_file_for", return_value=output):
                write_git_profile(
                    "profile",
                    "github",
                    "github.com",
                    "Augusto",
                    "augusto@example.com",
                    key,
                    "",
                )

            content = output.read_text()
            self.assertIn(f"sshCommand = ssh -i {key} -o IdentitiesOnly=yes", content)
            self.assertIn('[url "git@github.com:"]', content)
            self.assertIn("insteadOf = https://github.com/", content)
            self.assertNotIn("gpgSign = true", content)

    def test_ssh_success_message_counts_even_with_exit_code_one(self) -> None:
        completed = subprocess.CompletedProcess(
            ["ssh"],
            1,
            stdout="",
            stderr=(
                "Hi user! You've successfully authenticated, but GitHub does not "
                "provide shell access.\n"
            ),
        )
        with patch("holodeck.workflows.subprocess.run", return_value=completed):
            ok, detail = _ssh_test("github.com", Path("/tmp/key"))
        self.assertTrue(ok)
        self.assertIn("successfully authenticated", detail)

    def test_failed_key_upload_is_not_reported_as_success(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            public_key = Path(directory) / "key.pub"
            public_key.write_text("ssh-ed25519 AAAATEST comment\n")
            failed = subprocess.CompletedProcess(
                ["gh"],
                1,
                stdout="",
                stderr="HTTP 403: forbidden",
            )
            with (
                patch("holodeck.providers._github_key_exists", return_value=False),
                patch("holodeck.providers.subprocess.run", return_value=failed),
                patch(
                    "holodeck.providers.run",
                    return_value=Mock(returncode=1),
                ),
            ):
                with self.assertRaisesRegex(HolodeckError, "could not be registered"):
                    upload_github_ssh_key("github.com", "test", public_key)


if __name__ == "__main__":
    unittest.main()
