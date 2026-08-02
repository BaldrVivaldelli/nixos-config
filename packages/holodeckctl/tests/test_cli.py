from __future__ import annotations

import io
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Any

from holodeckctl.cli import run


class CliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.repo = Path(self.temporary.name)
        (self.repo / "flake.nix").write_text("{}\n", encoding="utf-8")
        (self.repo / "install.sh").write_text("#!/usr/bin/env bash\n", encoding="utf-8")
        self.environment = {
            "HOME": str(self.repo),
            "HOLODECK_REPO": str(self.repo),
            "PATH": "",
            "XDG_CONFIG_HOME": str(self.repo / ".config"),
        }

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def invoke(self, *args: str, runner: Any = subprocess.run) -> tuple[int, dict[str, Any], str]:
        stdout = io.StringIO()
        stderr = io.StringIO()
        code = run(
            list(args),
            environ=self.environment,
            stdout=stdout,
            stderr=stderr,
            runner=runner,
        )
        payload = json.loads(stdout.getvalue()) if stdout.getvalue() else {}
        return code, payload, stderr.getvalue()

    def test_status_uses_defaults_without_writing(self) -> None:
        code, payload, stderr = self.invoke("--json", "status")

        self.assertEqual(0, code)
        self.assertEqual("", stderr)
        self.assertTrue(payload["ok"])
        self.assertFalse(payload["exists"])
        self.assertEqual("defaults", payload["source"])
        self.assertEqual("home-manager", payload["ir"]["deployment"]["target"])
        self.assertEqual(
            {"aws", "github", "gitlab", "windowsVm"},
            set(payload["integrations"]),
        )
        self.assertFalse((self.repo / "holodeck.local.json").exists())

    def test_json_flag_also_works_after_command(self) -> None:
        code, payload, _ = self.invoke("status", "--json")

        self.assertEqual(0, code)
        self.assertEqual("status", payload["command"])

    def test_init_is_idempotent_and_force_resets(self) -> None:
        first_code, first, _ = self.invoke("--json", "init")
        second_code, second, _ = self.invoke("--json", "init")
        self.invoke("--json", "set", "appearance.theme.mode", "light")
        force_code, forced, _ = self.invoke("--json", "init", "--force")

        self.assertEqual((0, 0, 0), (first_code, second_code, force_code))
        self.assertTrue(first["changed"])
        self.assertFalse(second["changed"])
        self.assertTrue(forced["changed"])
        self.assertEqual("dark", forced["ir"]["appearance"]["theme"]["mode"])

    def test_set_initializes_and_validates(self) -> None:
        code, payload, _ = self.invoke(
            "--json", "set", "deployment.target", "existing-nixos"
        )

        self.assertEqual(0, code)
        self.assertTrue(payload["ok"])
        self.assertEqual("existing-nixos", payload["ir"]["deployment"]["target"])
        self.assertTrue((self.repo / "holodeck.local.json").is_file())

        invalid_code, invalid, _ = self.invoke(
            "--json", "set", "deployment.target", "wsl"
        )
        self.assertEqual(2, invalid_code)
        self.assertFalse(invalid["ok"])
        self.assertEqual("invalid-value", invalid["error"]["code"])

    def test_set_persists_windows_rdp_display_mode(self) -> None:
        code, payload, _ = self.invoke(
            "--json",
            "set",
            "integrations.windows.rdp.displayMode",
            "fullscreen",
        )

        self.assertEqual(0, code)
        self.assertEqual(
            "fullscreen",
            payload["ir"]["integrations"]["windows"]["rdp"]["displayMode"],
        )

    def test_plan_discloses_literal_argv_and_elevation(self) -> None:
        self.invoke("--json", "set", "deployment.target", "existing-nixos")
        code, payload, _ = self.invoke("--json", "plan")

        self.assertEqual(0, code)
        plan = payload["plan"]
        self.assertEqual(
            ["bash", str(self.repo / "install.sh"), "existing-nixos"], plan["argv"]
        )
        self.assertTrue(plan["requiresElevation"])
        self.assertTrue(plan["runInTerminal"])

    def test_apply_never_uses_a_shell_and_captures_json_output(self) -> None:
        self.invoke("--json", "init")
        calls: list[tuple[list[str], dict[str, Any]]] = []

        def fake_runner(argv: list[str], **kwargs: Any) -> subprocess.CompletedProcess[str]:
            calls.append((argv, kwargs))
            return subprocess.CompletedProcess(argv, 0, stdout="done\n", stderr="")

        code, payload, _ = self.invoke("--json", "apply", runner=fake_runner)

        self.assertEqual(0, code)
        self.assertTrue(payload["ok"])
        self.assertEqual("done\n", payload["stdout"])
        self.assertEqual(1, len(calls))
        argv, kwargs = calls[0]
        self.assertEqual(["bash", str(self.repo / "install.sh"), "home-manager"], argv)
        self.assertIs(kwargs["shell"], False)
        self.assertIs(kwargs["check"], False)
        self.assertEqual(self.repo, kwargs["cwd"])

    def test_plan_requires_a_persisted_ir(self) -> None:
        code, payload, _ = self.invoke("--json", "plan")

        self.assertEqual(2, code)
        self.assertEqual("missing-ir", payload["error"]["code"])

    def test_invalid_file_produces_stable_json_error(self) -> None:
        (self.repo / "holodeck.local.json").write_text("not json\n", encoding="utf-8")
        code, payload, stderr = self.invoke("--json", "status")

        self.assertEqual(2, code)
        self.assertEqual("", stderr)
        self.assertEqual({"code", "message"}, set(payload["error"]))
        self.assertEqual("invalid-json", payload["error"]["code"])

    def test_json_help_lists_contract(self) -> None:
        code, payload, _ = self.invoke("--json", "help")
        self.assertEqual(0, code)
        self.assertEqual("help", payload["command"])
        self.assertIn("deployment.target", payload["settable"])
        self.assertIn("integrations.windows.rdp.displayMode", payload["settable"])
        self.assertIn("github-setup", payload["actions"])
        self.assertIn("windows-up", payload["actions"])

    def test_interactive_actions_reject_json_output(self) -> None:
        code, payload, _ = self.invoke("--json", "action", "github-setup")

        self.assertEqual(2, code)
        self.assertEqual("usage", payload["error"]["code"])


if __name__ == "__main__":
    unittest.main()
