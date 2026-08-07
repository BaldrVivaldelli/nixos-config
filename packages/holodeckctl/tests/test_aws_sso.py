from __future__ import annotations

import configparser
import hashlib
import io
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Any

from holodeckctl.aws_sso import (
    MANAGED_BEGIN,
    MANAGED_END,
    _alias_request_path,
    _legacy_profile_key,
    _recommended_alias,
    _unique_profile_name,
    apply_aws_aliases,
    sync_aws_sso,
)
from holodeckctl.errors import ConfigCtlError


class FakePaginator:
    def __init__(self, operation: str, roles: dict[str, list[str]]) -> None:
        self.operation = operation
        self.roles = roles

    def paginate(self, **kwargs: Any) -> list[dict[str, Any]]:
        self.access_token = kwargs["accessToken"]
        if self.operation == "list_accounts":
            return [
                {
                    "accountList": [
                        {"accountId": "111111111111", "accountName": "Development"},
                    ]
                },
                {
                    "accountList": [
                        {"accountId": "222222222222", "accountName": "Production"},
                    ]
                },
            ]
        account_id = kwargs["accountId"]
        return [
            {"roleList": [{"roleName": role} for role in self.roles[account_id]]}
        ]


class FakeSsoClient:
    def __init__(self, roles: dict[str, list[str]]) -> None:
        self.roles = roles

    def get_paginator(self, operation_name: str) -> FakePaginator:
        return FakePaginator(operation_name, self.roles)


class AwsSsoTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.home = Path(self.temporary.name)
        self.bin = self.home / "bin"
        self.bin.mkdir()
        self.aws = self.bin / "aws"
        self.aws.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        self.aws.chmod(0o755)
        self.sso_url = "https://example.awsapps.com/start"
        self.environment = {
            "HOME": str(self.home),
            "PATH": str(self.bin),
            "AWS_DEFAULT_REGION": "us-east-1",
        }
        aws_dir = self.home / ".aws"
        aws_dir.mkdir()
        (aws_dir / "config").write_text(
            "# Keep this comment\n[profile manual]\nregion = sa-east-1\n",
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_token(self, token: str = "secret-access-token") -> None:
        cache = self.home / ".aws" / "sso" / "cache"
        cache.mkdir(parents=True, exist_ok=True)
        key = hashlib.sha1(b"holodeck").hexdigest()
        (cache / f"{key}.json").write_text(
            json.dumps({"accessToken": token}), encoding="utf-8"
        )

    def sso_input(self, prompt: str) -> str:
        if "URL" in prompt:
            return self.sso_url
        return ""

    def write_alias_request(
        self,
        assignments: list[dict[str, Any]],
        *,
        aliases: dict[str, str] | None = None,
        regions: dict[str, list[str]] | None = None,
    ) -> Path:
        aliases = aliases or {}
        regions = regions or {}
        request_path = _alias_request_path(self.environment)
        request_path.parent.mkdir(parents=True, exist_ok=True)
        request_path.write_text(
            json.dumps(
                {
                    "profiles": {
                        assignment["key"]: {
                            "alias": aliases.get(
                                assignment["roleName"], assignment["alias"]
                            ),
                            "regions": regions.get(
                                assignment["roleName"], ["us-east-1"]
                            ),
                        }
                        for assignment in assignments
                    },
                    "schemaVersion": 3,
                }
            ),
            encoding="utf-8",
        )
        return request_path

    def test_single_flow_generates_both_default_regions_for_every_assignment(self) -> None:
        calls: list[tuple[list[str], dict[str, Any]]] = []
        prompts: list[str] = []

        def runner(argv: list[str], **kwargs: Any) -> subprocess.CompletedProcess[str]:
            calls.append((argv, kwargs))
            self.write_token()
            return subprocess.CompletedProcess(argv, 0)

        def input_fn(prompt: str) -> str:
            prompts.append(prompt)
            return self.sso_input(prompt)

        output = io.StringIO()
        result = sync_aws_sso(
            self.environment,
            runner=runner,
            input_fn=input_fn,
            stdout=output,
            client_factory=lambda region: FakeSsoClient(
                {
                    "111111111111": ["DeveloperAccess", "ReadOnly"],
                    "222222222222": ["AdministratorAccess"],
                }
            ),
        )

        self.assertTrue(result["ok"])
        self.assertEqual(2, result["accountCount"])
        self.assertEqual(3, result["assignmentCount"])
        self.assertEqual(0, result["pendingRegionCount"])
        self.assertEqual(6, result["profileCount"])
        self.assertEqual(["AWS SSO start/issuer URL: "], prompts)
        self.assertEqual(
            [
                str(self.aws),
                "sso",
                "login",
                "--sso-session",
                "holodeck",
                "--no-cli-pager",
            ],
            calls[0][0],
        )
        self.assertIs(calls[0][1]["shell"], False)

        config = (self.home / ".aws" / "config").read_text(encoding="utf-8")
        self.assertIn("# Keep this comment", config)
        self.assertIn("[profile manual]", config)
        self.assertIn("[sso-session holodeck]", config)
        self.assertIn("[profile development-developeraccess-use1]", config)
        self.assertIn("[profile development-developeraccess-use2]", config)
        self.assertIn("[profile development-readonly-use1]", config)
        self.assertIn("[profile development-readonly-use2]", config)
        self.assertIn("[profile production-administratoraccess-use1]", config)
        self.assertIn("[profile production-administratoraccess-use2]", config)
        self.assertTrue(all(not item["pending"] for item in result["assignments"]))
        self.assertEqual(1, config.count(MANAGED_BEGIN))
        self.assertEqual(1, config.count(MANAGED_END))
        self.assertNotIn("secret-access-token", config)
        self.assertNotIn("secret-access-token", output.getvalue())
        self.assertEqual(0o600, (self.home / ".aws" / "config").stat().st_mode & 0o777)

    def test_resync_replaces_only_the_managed_block(self) -> None:
        def runner(argv: list[str], **_kwargs: Any) -> subprocess.CompletedProcess[str]:
            self.write_token("rotated-token")
            return subprocess.CompletedProcess(argv, 0)

        first_roles = {
            "111111111111": ["DeveloperAccess"],
            "222222222222": ["AdministratorAccess"],
        }
        first = sync_aws_sso(
            self.environment,
            runner=runner,
            input_fn=self.sso_input,
            stdout=io.StringIO(),
            client_factory=lambda _region: FakeSsoClient(first_roles),
        )
        self.write_alias_request(first["assignments"])
        apply_aws_aliases(self.environment)
        second_roles = {
            "111111111111": ["ReadOnly"],
            "222222222222": ["AdministratorAccess"],
        }
        second = sync_aws_sso(
            self.environment,
            runner=runner,
            input_fn=lambda prompt: self.fail(f"prompt inesperado: {prompt}"),
            stdout=io.StringIO(),
            client_factory=lambda _region: FakeSsoClient(second_roles),
        )

        config = (self.home / ".aws" / "config").read_text(encoding="utf-8")
        self.assertIn("# Keep this comment", config)
        self.assertIn("[profile manual]", config)
        self.assertNotIn("[profile development-developeraccess-use1]", config)
        self.assertIn("[profile development-readonly-use1]", config)
        self.assertIn("[profile development-readonly-use2]", config)
        self.assertIn("[profile production-administratoraccess-use1]", config)
        readonly = next(
            assignment
            for assignment in second["assignments"]
            if assignment["roleName"] == "ReadOnly"
        )
        self.assertFalse(readonly["pending"])
        self.assertEqual(["us-east-1", "us-east-2"], readonly["regions"])
        self.assertEqual(1, config.count("[sso-session holodeck]"))
        self.assertEqual(1, config.count(MANAGED_BEGIN))

    def test_profile_names_distinguish_target_regions(self) -> None:
        reserved: set[str] = set()

        east = _unique_profile_name(
            "production-administratoraccess", "222222222222", "us-east-1", reserved
        )
        south = _unique_profile_name(
            "production-administratoraccess", "222222222222", "us-east-2", reserved
        )

        self.assertEqual("production-administratoraccess-use1", east)
        self.assertEqual("production-administratoraccess-use2", south)

    def test_profile_name_collisions_keep_region_and_add_account_suffix(self) -> None:
        reserved: set[str] = set()

        first = _unique_profile_name(
            "lp-prd-ro", "111111111111", "us-east-1", reserved
        )
        second = _unique_profile_name(
            "lp-prd-ro", "222222222222", "us-east-1", reserved
        )

        self.assertEqual("lp-prd-ro-use1", first)
        self.assertEqual("lp-prd-ro-use1-2222", second)

    def test_recommendations_handle_new_profiles_without_known_aliases(self) -> None:
        self.assertEqual(
            "dp-prd-ro",
            _recommended_alias(
                "DataPlatform-prd", "333333333333", "ReadOnlyAccess"
            ),
        )
        self.assertEqual(
            "datap-prd-co",
            _recommended_alias(
                "dataplatform-prd", "333333333333", "CustomOperator"
            ),
        )

    def test_alias_request_generates_one_profile_per_confirmed_region(self) -> None:
        def runner(argv: list[str], **_kwargs: Any) -> subprocess.CompletedProcess[str]:
            self.write_token()
            return subprocess.CompletedProcess(argv, 0)

        result = sync_aws_sso(
            self.environment,
            runner=runner,
            input_fn=self.sso_input,
            stdout=io.StringIO(),
            client_factory=lambda _region: FakeSsoClient(
                {
                    "111111111111": ["DeveloperAccess"],
                    "222222222222": ["AdministratorAccess"],
                }
            ),
        )
        development = next(
            assignment
            for assignment in result["assignments"]
            if assignment["roleName"] == "DeveloperAccess"
        )
        production = next(
            assignment
            for assignment in result["assignments"]
            if assignment["roleName"] == "AdministratorAccess"
        )
        request_path = self.write_alias_request(
            result["assignments"],
            aliases={
                "DeveloperAccess": "platform-dev",
                "AdministratorAccess": production["suggestedAlias"],
            },
            regions={
                "DeveloperAccess": ["us-east-1", "us-east-2"],
                "AdministratorAccess": ["us-east-1"],
            },
        )

        applied = apply_aws_aliases(self.environment)

        self.assertTrue(applied["changed"])
        self.assertEqual(2, applied["assignmentCount"])
        self.assertEqual(3, applied["profileCount"])
        config = (self.home / ".aws" / "config").read_text(encoding="utf-8")
        self.assertIn("[profile platform-dev-use1]", config)
        self.assertIn("[profile platform-dev-use2]", config)
        self.assertIn("[profile produ-admin-use1]", config)
        self.assertNotIn("[profile development-developeraccess-use1]", config)
        parser = configparser.RawConfigParser()
        parser.read_string(config)
        self.assertEqual(
            "us-east-1", parser.get("profile platform-dev-use1", "region")
        )
        self.assertEqual(
            "us-east-2", parser.get("profile platform-dev-use2", "region")
        )
        self.assertEqual(
            "us-east-1", parser.get("profile produ-admin-use1", "region")
        )
        self.assertFalse(request_path.exists())
        preferences_text = (
            self.home / ".config" / "holodeck" / "aws-aliases.json"
        ).read_text(encoding="utf-8")
        preferences = json.loads(preferences_text)
        self.assertEqual(3, preferences["schemaVersion"])
        self.assertEqual(
            ["us-east-1", "us-east-2"],
            preferences["profiles"][development["key"]]["regions"],
        )
        self.assertNotIn("111111111111", preferences_text)
        self.assertNotIn("DeveloperAccess", preferences_text)
        self.assertEqual(
            0o600,
            (self.home / ".config" / "holodeck" / "aws-aliases.json")
            .stat()
            .st_mode
            & 0o777,
        )

    def test_resync_preserves_confirmed_regions_and_defaults_new_assignments_to_both(self) -> None:
        def runner(argv: list[str], **_kwargs: Any) -> subprocess.CompletedProcess[str]:
            self.write_token()
            return subprocess.CompletedProcess(argv, 0)

        first = sync_aws_sso(
            self.environment,
            runner=runner,
            input_fn=self.sso_input,
            stdout=io.StringIO(),
            client_factory=lambda _region: FakeSsoClient(
                {
                    "111111111111": ["DeveloperAccess"],
                    "222222222222": ["AdministratorAccess"],
                }
            ),
        )
        self.write_alias_request(
            first["assignments"],
            aliases={"DeveloperAccess": "platform-dev"},
            regions={"DeveloperAccess": ["us-east-2"]},
        )
        apply_aws_aliases(self.environment)

        second = sync_aws_sso(
            self.environment,
            runner=runner,
            input_fn=lambda prompt: self.fail(f"prompt inesperado: {prompt}"),
            stdout=io.StringIO(),
            client_factory=lambda _region: FakeSsoClient(
                {
                    "111111111111": ["DeveloperAccess", "ReadOnlyAccess"],
                    "222222222222": ["AdministratorAccess"],
                }
            ),
        )
        profiles_by_role = {
            profile["roleName"]: profile for profile in second["profiles"]
        }
        assignments_by_role = {
            assignment["roleName"]: assignment
            for assignment in second["assignments"]
        }

        self.assertEqual(
            "platform-dev-use2", profiles_by_role["DeveloperAccess"]["name"]
        )
        self.assertEqual(
            "us-east-2", profiles_by_role["DeveloperAccess"]["region"]
        )
        self.assertFalse(assignments_by_role["ReadOnlyAccess"]["pending"])
        self.assertEqual(
            ["us-east-1", "us-east-2"],
            assignments_by_role["ReadOnlyAccess"]["regions"],
        )
        self.assertEqual(
            "devel-ro", assignments_by_role["ReadOnlyAccess"]["suggestedAlias"]
        )
        readonly_names = {
            profile["name"]
            for profile in second["profiles"]
            if profile["roleName"] == "ReadOnlyAccess"
        }
        self.assertEqual(
            {
                "development-readonlyaccess-use1",
                "development-readonlyaccess-use2",
            },
            readonly_names,
        )

    def test_resync_migrates_v2_aliases_and_adds_both_default_regions(self) -> None:
        def runner(argv: list[str], **_kwargs: Any) -> subprocess.CompletedProcess[str]:
            self.write_token()
            return subprocess.CompletedProcess(argv, 0)

        roles = {
            "111111111111": ["DeveloperAccess"],
            "222222222222": ["AdministratorAccess"],
        }
        initial = sync_aws_sso(
            self.environment,
            runner=runner,
            input_fn=self.sso_input,
            stdout=io.StringIO(),
            client_factory=lambda _region: FakeSsoClient(roles),
        )

        catalog_path = (
            self.home / ".local" / "state" / "holodeck" / "aws-sso-catalog.json"
        )
        account_ids = {
            "DeveloperAccess": "111111111111",
            "AdministratorAccess": "222222222222",
        }
        old_profiles = []
        old_preferences = {}
        for assignment in initial["assignments"]:
            region = "us-east-2" if assignment["roleName"] == "DeveloperAccess" else "us-east-1"
            alias = "legacy-dev" if assignment["roleName"] == "DeveloperAccess" else assignment["alias"]
            old_profiles.append(
                {
                    **assignment,
                    "accountId": account_ids[assignment["roleName"]],
                    "alias": alias,
                    "name": f"{alias}-{'use2' if region == 'us-east-2' else 'use1'}",
                    "region": region,
                    "regionAlias": "use2" if region == "us-east-2" else "use1",
                }
            )
            old_preferences[assignment["key"]] = {
                "alias": alias,
                "region": region,
            }
        catalog_path.write_text(
            json.dumps(
                {
                    "defaultRegion": "us-east-1",
                    "profiles": old_profiles,
                    "schemaVersion": 2,
                    "sessionName": "holodeck",
                }
            ),
            encoding="utf-8",
        )
        aliases_path = self.home / ".config" / "holodeck" / "aws-aliases.json"
        aliases_path.write_text(
            json.dumps({"profiles": old_preferences, "schemaVersion": 2}),
            encoding="utf-8",
        )

        result = sync_aws_sso(
            self.environment,
            runner=runner,
            input_fn=lambda prompt: self.fail(f"prompt inesperado: {prompt}"),
            stdout=io.StringIO(),
            client_factory=lambda _region: FakeSsoClient(roles),
        )

        development = next(
            assignment
            for assignment in result["assignments"]
            if assignment["roleName"] == "DeveloperAccess"
        )
        self.assertEqual("legacy-dev", development["alias"])
        self.assertEqual(["us-east-1", "us-east-2"], development["regions"])
        self.assertEqual([], development["suggestedRegions"])
        self.assertFalse(development["pending"])
        self.assertEqual(4, result["profileCount"])
        migrated_catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
        migrated_preferences = json.loads(aliases_path.read_text(encoding="utf-8"))
        self.assertEqual(3, migrated_catalog["schemaVersion"])
        self.assertEqual(3, migrated_preferences["schemaVersion"])
        self.assertIn(development["key"], migrated_preferences["profiles"])

        self.write_alias_request(
            result["assignments"],
            regions={"DeveloperAccess": ["us-east-2"]},
        )
        applied = apply_aws_aliases(self.environment)
        self.assertIn(
            "legacy-dev-use2", [profile["name"] for profile in applied["profiles"]]
        )

    def test_resync_migrates_v1_region_keys_to_both_default_regions(self) -> None:
        def runner(argv: list[str], **_kwargs: Any) -> subprocess.CompletedProcess[str]:
            self.write_token()
            return subprocess.CompletedProcess(argv, 0)

        roles = {
            "111111111111": ["DeveloperAccess"],
            "222222222222": ["AdministratorAccess"],
        }
        initial = sync_aws_sso(
            self.environment,
            runner=runner,
            input_fn=self.sso_input,
            stdout=io.StringIO(),
            client_factory=lambda _region: FakeSsoClient(roles),
        )
        account_ids = {
            "DeveloperAccess": "111111111111",
            "AdministratorAccess": "222222222222",
        }
        old_profiles = []
        old_aliases = {}
        for assignment in initial["assignments"]:
            region = "us-east-2"
            account_id = account_ids[assignment["roleName"]]
            legacy_key = _legacy_profile_key(
                "holodeck", account_id, assignment["roleName"], region
            )
            old_profiles.append(
                {
                    **assignment,
                    "accountId": account_id,
                    "key": legacy_key,
                    "name": f"{assignment['alias']}-use2",
                    "region": region,
                    "regionAlias": "use2",
                }
            )
            if assignment["roleName"] == "DeveloperAccess":
                old_aliases[legacy_key] = "v1-dev"

        catalog_path = (
            self.home / ".local" / "state" / "holodeck" / "aws-sso-catalog.json"
        )
        catalog_path.write_text(
            json.dumps(
                {
                    "defaultRegion": "us-east-1",
                    "profiles": old_profiles,
                    "schemaVersion": 1,
                    "sessionName": "holodeck",
                }
            ),
            encoding="utf-8",
        )
        aliases_path = self.home / ".config" / "holodeck" / "aws-aliases.json"
        aliases_path.write_text(
            json.dumps({"aliases": old_aliases, "schemaVersion": 1}),
            encoding="utf-8",
        )

        migrated = sync_aws_sso(
            self.environment,
            runner=runner,
            input_fn=lambda prompt: self.fail(f"prompt inesperado: {prompt}"),
            stdout=io.StringIO(),
            client_factory=lambda _region: FakeSsoClient(roles),
        )
        development = next(
            assignment
            for assignment in migrated["assignments"]
            if assignment["roleName"] == "DeveloperAccess"
        )

        self.assertEqual("v1-dev", development["alias"])
        self.assertEqual(["us-east-1", "us-east-2"], development["regions"])
        self.assertEqual([], development["suggestedRegions"])
        self.assertFalse(development["pending"])

    def test_region_editor_rejects_an_invalid_region(self) -> None:
        def runner(argv: list[str], **_kwargs: Any) -> subprocess.CompletedProcess[str]:
            self.write_token()
            return subprocess.CompletedProcess(argv, 0)

        result = sync_aws_sso(
            self.environment,
            runner=runner,
            input_fn=self.sso_input,
            stdout=io.StringIO(),
            client_factory=lambda _region: FakeSsoClient(
                {
                    "111111111111": ["DeveloperAccess"],
                    "222222222222": ["AdministratorAccess"],
                }
            ),
        )
        self.write_alias_request(
            result["assignments"],
            regions={"DeveloperAccess": ["useast2"]},
        )

        with self.assertRaises(ConfigCtlError) as raised:
            apply_aws_aliases(self.environment)

        self.assertEqual("invalid-aws-region", raised.exception.code)

    def test_region_editor_requires_every_assignment_to_have_a_region(self) -> None:
        def runner(argv: list[str], **_kwargs: Any) -> subprocess.CompletedProcess[str]:
            self.write_token()
            return subprocess.CompletedProcess(argv, 0)

        result = sync_aws_sso(
            self.environment,
            runner=runner,
            input_fn=self.sso_input,
            stdout=io.StringIO(),
            client_factory=lambda _region: FakeSsoClient(
                {
                    "111111111111": ["DeveloperAccess"],
                    "222222222222": ["AdministratorAccess"],
                }
            ),
        )
        self.write_alias_request(
            result["assignments"],
            regions={"DeveloperAccess": []},
        )

        with self.assertRaises(ConfigCtlError) as raised:
            apply_aws_aliases(self.environment)

        self.assertEqual("missing-aws-region", raised.exception.code)

    def test_resync_reuses_the_local_url_without_prompting_again(self) -> None:
        configs_at_login: list[str] = []

        def runner(argv: list[str], **_kwargs: Any) -> subprocess.CompletedProcess[str]:
            configs_at_login.append(
                (self.home / ".aws" / "config").read_text(encoding="utf-8")
            )
            self.write_token()
            return subprocess.CompletedProcess(argv, 0)

        roles = {
            "111111111111": ["DeveloperAccess"],
            "222222222222": ["AdministratorAccess"],
        }
        sync_aws_sso(
            self.environment,
            runner=runner,
            input_fn=self.sso_input,
            stdout=io.StringIO(),
            client_factory=lambda _region: FakeSsoClient(roles),
        )

        sync_aws_sso(
            self.environment,
            runner=runner,
            input_fn=lambda prompt: self.fail(f"prompt inesperado: {prompt}"),
            stdout=io.StringIO(),
            client_factory=lambda _region: FakeSsoClient(roles),
        )

        self.assertIn(f"sso_start_url = {self.sso_url}", configs_at_login[1])
        self.assertIn("sso_region = us-east-1", configs_at_login[1])

    def test_discovery_errors_never_echo_the_access_token(self) -> None:
        token = "secret-that-must-not-be-reported"

        class FailingPaginator:
            def paginate(self, **kwargs: Any) -> list[dict[str, Any]]:
                raise RuntimeError(kwargs["accessToken"])

        class FailingClient:
            def get_paginator(self, _operation: str) -> FailingPaginator:
                return FailingPaginator()

        def runner(argv: list[str], **_kwargs: Any) -> subprocess.CompletedProcess[str]:
            self.write_token(token)
            return subprocess.CompletedProcess(argv, 0)

        with self.assertRaises(ConfigCtlError) as raised:
            sync_aws_sso(
                self.environment,
                runner=runner,
                input_fn=self.sso_input,
                stdout=io.StringIO(),
                client_factory=lambda _region: FailingClient(),
            )

        self.assertEqual("aws-discovery-failed", raised.exception.code)
        self.assertNotIn(token, str(raised.exception))


if __name__ == "__main__":
    unittest.main()
