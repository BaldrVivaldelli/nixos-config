from __future__ import annotations

import errno
import fcntl
import json
import os
import tempfile
import time
from collections.abc import Iterator, Mapping
from contextlib import contextmanager
from pathlib import Path
from typing import Any

from .errors import ConfigCtlError
from .model import validate_ir


def load_ir(path: Path) -> dict[str, Any]:
    try:
        raw = path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise ConfigCtlError("missing-ir", f"no existe el IR: {path}") from exc
    except OSError as exc:
        raise ConfigCtlError("read-failed", f"no se pudo leer {path}: {exc}") from exc

    def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        value: dict[str, Any] = {}
        for key, item in pairs:
            if key in value:
                raise ConfigCtlError("invalid-json", f"clave JSON duplicada en {path}: {key}")
            value[key] = item
        return value

    try:
        value = json.loads(raw, object_pairs_hook=reject_duplicate_keys)
    except json.JSONDecodeError as exc:
        raise ConfigCtlError(
            "invalid-json",
            f"JSON inválido en {path} (línea {exc.lineno}, columna {exc.colno})",
        ) from exc
    return validate_ir(value)


@contextmanager
def exclusive_lock(ir_path: Path, timeout: float) -> Iterator[None]:
    ir_path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = Path(f"{ir_path}.lock")
    try:
        descriptor = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    except OSError as exc:
        raise ConfigCtlError(
            "lock-failed", f"no se pudo abrir el lock {lock_path}: {exc}"
        ) from exc

    deadline = time.monotonic() + timeout
    try:
        while True:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError as exc:
                if exc.errno not in (errno.EACCES, errno.EAGAIN):
                    raise ConfigCtlError(
                        "lock-failed", f"no se pudo adquirir el lock {lock_path}: {exc}"
                    ) from exc
                if time.monotonic() >= deadline:
                    raise ConfigCtlError(
                        "lock-timeout",
                        f"otro proceso está modificando o aplicando {ir_path}",
                    ) from exc
                time.sleep(min(0.05, max(0.0, deadline - time.monotonic())))
        yield
    finally:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
        finally:
            os.close(descriptor)


def atomic_write_ir(path: Path, ir: Mapping[str, Any]) -> None:
    normalized = validate_ir(ir)
    path.parent.mkdir(parents=True, exist_ok=True)
    serialized = json.dumps(normalized, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    temporary_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary:
            temporary_name = temporary.name
            os.chmod(temporary.name, 0o600)
            temporary.write(serialized)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_name, path)
        temporary_name = None

        directory_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except OSError as exc:
        raise ConfigCtlError("write-failed", f"no se pudo escribir {path}: {exc}") from exc
    finally:
        if temporary_name is not None:
            try:
                os.unlink(temporary_name)
            except FileNotFoundError:
                pass
