from __future__ import annotations

import unittest
from unittest.mock import patch

from holodeck.errors import HolodeckError
from holodeck.workflows import require_user_context


class UserContextTests(unittest.TestCase):
    def test_rejects_root_for_personal_state(self) -> None:
        with patch("holodeck.workflows.os.geteuid", return_value=0):
            with self.assertRaisesRegex(HolodeckError, "sin sudo"):
                require_user_context()

    def test_accepts_regular_user(self) -> None:
        with patch("holodeck.workflows.os.geteuid", return_value=1000):
            require_user_context()


if __name__ == "__main__":
    unittest.main()
