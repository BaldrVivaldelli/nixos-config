"""CLI for the optional NixOS-WSL backend."""

from __future__ import annotations

import subprocess
import sys

from holodeck.errors import HolodeckError
from holodeck.process import format_cmd
from holodeck.ui import ui

from .installer import install_nixos


def usage() -> None:
    print(
        """Usage: holodeck-system-nixos <command>

Commands:
  install --target wsl
  help

This optional backend installs the declared NixOS-WSL target. It does not
inspect, partition, format or mount physical disks."""
    )


def dispatch(args: list[str]) -> int:
    command = args[0] if args else "help"
    rest = args[1:]
    if command == "install":
        install_nixos(rest)
    elif command in {"help", "-h", "--help"}:
        usage()
    else:
        usage()
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    try:
        return dispatch(args)
    except HolodeckError as exc:
        ui.error(str(exc))
        return 1
    except subprocess.CalledProcessError as exc:
        ui.error(f"Command failed: {format_cmd(exc.cmd)}")
        return exc.returncode or 1
    except KeyboardInterrupt:
        print()
        ui.warn("Cancelled.")
        return 130
