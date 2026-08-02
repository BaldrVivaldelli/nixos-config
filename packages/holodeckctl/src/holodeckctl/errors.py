from __future__ import annotations


class ConfigCtlError(Exception):
    """Expected, user-facing error with a stable machine-readable code."""

    def __init__(self, code: str, message: str, *, exit_code: int = 2) -> None:
        super().__init__(message)
        self.code = code
        self.exit_code = exit_code
