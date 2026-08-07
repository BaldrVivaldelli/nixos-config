"""Regression tests for the authentication-only GitLab workflow."""

from __future__ import annotations

import subprocess
import unittest
from unittest.mock import patch

from holodeck.errors import HolodeckError
from holodeck.providers import login_gitlab
from holodeck.workflows import authenticate_gitlab, normalize_gitlab_url


class GitlabFlowTests(unittest.TestCase):
    def test_instance_url_accepts_a_host_and_removes_trailing_slash(self) -> None:
        self.assertEqual(
            ("https://gitlab.example.com", "gitlab.example.com", "https"),
            normalize_gitlab_url("gitlab.example.com/"),
        )

    def test_instance_url_accepts_group_and_subgroup_paths(self) -> None:
        self.assertEqual(
            ("https://gitlab.com/nave-negocios", "gitlab.com", "https"),
            normalize_gitlab_url("https://gitlab.com/nave-negocios/"),
        )
        self.assertEqual(
            (
                "https://gitlab.example.com/group/subgroup",
                "gitlab.example.com",
                "https",
            ),
            normalize_gitlab_url("gitlab.example.com/group/subgroup"),
        )

    def test_instance_url_rejects_credentials_and_unsafe_paths(self) -> None:
        for value in (
            "https://user@gitlab.example.com",
            "ssh://gitlab.example.com",
            "https://gitlab.example.com/group?private=true",
            "https://gitlab.example.com/group#projects",
            "https://gitlab.example.com/group/%2Fproject",
            "https://gitlab.example.com/group/..",
        ):
            with self.subTest(value=value), self.assertRaises(HolodeckError):
                normalize_gitlab_url(value)

    def test_login_uses_web_oauth_without_other_prompts(self) -> None:
        completed = subprocess.CompletedProcess(["glab"], 0)
        with (
            patch("holodeck.providers.command_ok", return_value=False),
            patch("holodeck.providers.run", return_value=completed) as runner,
        ):
            login_gitlab("gitlab.example.com")

        self.assertEqual(1, runner.call_count)
        args = runner.call_args.args[0]
        self.assertIn("--web", args)
        self.assertIn("--git-protocol", args)
        self.assertEqual("https", args[args.index("--git-protocol") + 1])
        self.assertEqual("gitlab.example.com", args[args.index("--hostname") + 1])

    def test_failed_web_login_never_falls_back_to_a_manual_token(self) -> None:
        completed = subprocess.CompletedProcess(["glab"], 1)
        with (
            patch("holodeck.providers.command_ok", return_value=False),
            patch("holodeck.providers.run", return_value=completed) as runner,
            self.assertRaisesRegex(HolodeckError, "will not request or store a token"),
        ):
            login_gitlab("gitlab.example.com")

        self.assertEqual(1, runner.call_count)

    def test_group_url_only_authenticates_the_host(self) -> None:
        with (
            patch(
                "holodeck.workflows.prompt",
                return_value="https://gitlab.com/nave-negocios",
            ) as ask,
            patch("holodeck.workflows.profiles", return_value=[]),
            patch("holodeck.workflows.login_gitlab") as login,
            patch("holodeck.workflows.write_local_profile") as write_profile,
        ):
            authenticate_gitlab()

        ask.assert_called_once_with("GitLab URL", "")
        login.assert_called_once_with("gitlab.com", "https")
        write_profile.assert_not_called()

if __name__ == "__main__":
    unittest.main()
