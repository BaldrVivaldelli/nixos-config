"""Tests for cross-platform adapters."""

from __future__ import annotations

import unittest
from unittest.mock import patch

from holodeck.platform import open_url


class PlatformTests(unittest.TestCase):
    def test_open_url_uses_python_cross_platform_adapter(self) -> None:
        with patch("holodeck.platform.webbrowser.open", return_value=True) as opener:
            self.assertTrue(open_url("https://example.com"))

        opener.assert_called_once_with("https://example.com", new=2)


if __name__ == "__main__":
    unittest.main()
