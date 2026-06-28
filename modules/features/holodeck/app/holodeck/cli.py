from __future__ import annotations

import subprocess
import sys

from .errors import HolodeckError
from .process import format_cmd
from .ui import ui
from .workflows import (
    auth_command,
    doctor,
    profile_command,
    purge,
    setup,
)


def usage() -> None:
    print(
        """Usage: holodeck <command>

Recommended first run:
  holodeck setup        Full wizard: auth + SSH/GPG + Git profiles

Commands:
  setup                 Full wizard for GitHub personal and/or GitLab work
  github                Configure GitHub from your authenticated account
  gitlab                Configure one GitLab profile
  login github          Only authenticate GitHub; does not configure Git
  login gitlab          Only authenticate GitLab; does not configure Git
  auth github           Alias for login github
  auth gitlab           Alias for login gitlab
  profile github        Alias for github
  profile gitlab        Alias for gitlab
  doctor                Show profiles, auth state, and key files
  purge                 Remove Holodeck-managed local profiles, keys, and auth
  clean                 Alias for purge
  sanitize              Alias for purge

Holodeck stores generated local state under ~/.config/holodeck and only writes
managed blocks in ~/.gitconfig and ~/.ssh/config."""
    )


def dispatch(args: list[str]) -> int:
    command = args[0] if args else "help"
    rest = args[1:]

    if command == "setup":
        setup()
    elif command == "github":
        profile_command("github")
    elif command == "gitlab":
        profile_command("gitlab")
    elif command in {"auth", "login"}:
        auth_command(rest[0] if rest else "")
    elif command == "profile":
        profile_command(rest[0] if rest else "")
    elif command in {"doctor", "status"}:
        doctor()
    elif command in {"purge", "clean", "sanitize"}:
        purge()
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

