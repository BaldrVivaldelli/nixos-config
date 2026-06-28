from __future__ import annotations

import os
import sys


class Ui:
    colors = {
        "blue": "\033[34m",
        "green": "\033[32m",
        "yellow": "\033[33m",
        "red": "\033[31m",
        "cyan": "\033[36m",
        "bold": "\033[1m",
        "reset": "\033[0m",
    }

    def __init__(self) -> None:
        self.enabled = sys.stdout.isatty() and "NO_COLOR" not in os.environ

    def color(self, text: str, name: str) -> str:
        if not self.enabled:
            return text
        return f"{self.colors[name]}{text}{self.colors['reset']}"

    def heading(self, text: str) -> None:
        print(self.color(text, "bold"))

    def ok(self, text: str) -> None:
        print(f"{self.color('ok', 'green')} {text}")

    def info(self, text: str) -> None:
        print(f"{self.color('info', 'cyan')} {text}")

    def warn(self, text: str) -> None:
        print(f"{self.color('warn', 'yellow')} {text}")

    def error(self, text: str) -> None:
        print(f"{self.color('error', 'red')} {text}", file=sys.stderr)

    def label(self, text: str) -> str:
        return self.color(text, "blue")


ui = Ui()

