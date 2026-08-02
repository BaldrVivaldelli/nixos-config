from __future__ import annotations

import unittest

from holodeckctl.errors import ConfigCtlError
from holodeckctl.model import default_ir, digest_ir, set_value, validate_ir


class ModelTests(unittest.TestCase):
    def test_defaults_are_valid_and_independent(self) -> None:
        first = default_ir()
        second = default_ir()
        first["appearance"]["theme"]["mode"] = "light"

        self.assertEqual("dark", second["appearance"]["theme"]["mode"])
        self.assertEqual(second, validate_ir(second))

    def test_rejects_unknown_keys(self) -> None:
        ir = default_ir()
        ir["desktop"]["surprise"] = True

        with self.assertRaisesRegex(ConfigCtlError, "claves desconocidas"):
            validate_ir(ir)

    def test_rejects_unknown_enum_values(self) -> None:
        ir = default_ir()
        ir["desktop"]["compositor"] = "hyprland"

        with self.assertRaisesRegex(ConfigCtlError, "desktop.compositor"):
            validate_ir(ir)

    def test_rejects_unsupported_schema(self) -> None:
        ir = default_ir()
        ir["schemaVersion"] = 2

        with self.assertRaises(ConfigCtlError) as raised:
            validate_ir(ir)
        self.assertEqual("unsupported-schema", raised.exception.code)

    def test_set_only_accepts_allowlisted_keys_and_values(self) -> None:
        updated = set_value(default_ir(), "appearance.theme.mode", "light")
        self.assertEqual("light", updated["appearance"]["theme"]["mode"])

        with self.assertRaises(ConfigCtlError) as raised:
            set_value(updated, "appearance.theme.mode", "automatic")
        self.assertEqual("invalid-value", raised.exception.code)

        with self.assertRaises(ConfigCtlError) as raised:
            set_value(updated, "desktop.command", "anything")
        self.assertEqual("unknown-key", raised.exception.code)

    def test_builtin_theme_must_be_non_empty_single_line(self) -> None:
        updated = set_value(default_ir(), "appearance.theme.builtin", "  Nord  ")
        self.assertEqual("Nord", updated["appearance"]["theme"]["builtin"])

        for invalid in ("", "   ", "Nord\nother", "Nord\x00other"):
            with self.subTest(invalid=invalid):
                with self.assertRaises(ConfigCtlError):
                    set_value(default_ir(), "appearance.theme.builtin", invalid)

    def test_digest_is_stable(self) -> None:
        self.assertEqual(digest_ir(default_ir()), digest_ir(validate_ir(default_ir())))
        self.assertRegex(digest_ir(default_ir()), r"^sha256:[0-9a-f]{64}$")


if __name__ == "__main__":
    unittest.main()
