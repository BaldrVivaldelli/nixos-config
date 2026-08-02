from __future__ import annotations

import multiprocessing
import tempfile
import unittest
from pathlib import Path
from typing import Any

from holodeckctl.errors import ConfigCtlError
from holodeckctl.model import default_ir
from holodeckctl.storage import atomic_write_ir, exclusive_lock, load_ir


def lock_worker(path: str, entered: Any, release: Any) -> None:
    with exclusive_lock(Path(path), 1):
        entered.set()
        release.wait(5)


class StorageTests(unittest.TestCase):
    def test_atomic_round_trip_and_permissions(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "nested" / "holodeck.local.json"
            atomic_write_ir(path, default_ir())

            self.assertEqual(default_ir(), load_ir(path))
            self.assertEqual(0o600, path.stat().st_mode & 0o777)
            self.assertFalse(list(path.parent.glob(f".{path.name}.*.tmp")))

    def test_rejects_duplicate_json_keys(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "holodeck.local.json"
            path.write_text('{"schemaVersion":1,"schemaVersion":1}', encoding="utf-8")

            with self.assertRaises(ConfigCtlError) as raised:
                load_ir(path)
            self.assertEqual("invalid-json", raised.exception.code)

    def test_lock_times_out_when_another_process_holds_it(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "holodeck.local.json"
            entered = multiprocessing.Event()
            release = multiprocessing.Event()
            process = multiprocessing.Process(
                target=lock_worker, args=(str(path), entered, release)
            )
            process.start()
            self.assertTrue(entered.wait(2))
            try:
                with self.assertRaises(ConfigCtlError) as raised:
                    with exclusive_lock(path, 0):
                        pass
                self.assertEqual("lock-timeout", raised.exception.code)
            finally:
                release.set()
                process.join(2)
                if process.is_alive():
                    process.terminate()
                    process.join()


if __name__ == "__main__":
    unittest.main()
