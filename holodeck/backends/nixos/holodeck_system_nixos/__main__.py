"""Module entrypoint for the NixOS backend."""

from .cli import main


if __name__ == "__main__":
    raise SystemExit(main())
