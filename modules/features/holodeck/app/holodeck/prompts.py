from __future__ import annotations

from .ui import ui


def prompt(label: str, default: str = "") -> str:
    if default:
        value = input(f"{ui.label(label)} [{default}]: ")
        return value or default
    return input(f"{ui.label(label)}: ")


def confirm(label: str, default: str = "yes") -> bool:
    if default == "yes":
        answer = input(f"{ui.label(label)} [Y/n]: ") or "y"
        return answer in {"y", "Y", "yes", "YES"}
    answer = input(f"{ui.label(label)} [y/N]: ") or "n"
    return answer in {"y", "Y", "yes", "YES"}

