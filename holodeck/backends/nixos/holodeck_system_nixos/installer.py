"""NixOS-WSL installation backend for Holodeck."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from holodeck.errors import HolodeckError
from holodeck.process import run
from holodeck.ui import ui


SUPPORTED_TARGETS = ("wsl",)
DEFAULT_WSL_USER = os.environ.get("HOLODECK_NIXOS_WSL_USER", "nixos")
DEFAULT_WSL_HOST_NAME = os.environ.get(
    "HOLODECK_NIXOS_WSL_HOST_NAME", "nixos-wsl"
)
DEFAULT_REPO_PATH = os.environ.get(
    "HOLODECK_NIXOS_REPO_PATH",
    f"/home/{DEFAULT_WSL_USER}/projects/personal/nixos-config",
)
COMMON_INSTALL_INPUTS = (
    "flake.nix",
    "flake.lock",
    "inventory.nix",
    "configure-inventory.sh",
    "install.sh",
    "lib",
    "holodeck/core",
    "holodeck/backends/nixos",
    "home",
    "modules/home",
    "modules/nixos",
)
WSL_INSTALL_INPUTS = ("modules/hosts/wsl",)


class _ArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise HolodeckError(f"{message}\n\n{self.format_help().rstrip()}")


@dataclass(frozen=True)
class InstallRequest:
    target: str
    repo: Path


def parse_install_args(args: list[str]) -> InstallRequest:
    parser = _ArgumentParser(
        prog="holodeck-system-nixos install",
        description="Instala el target NixOS-WSL declarado por este repositorio.",
    )
    parser.add_argument("--target", required=True, choices=SUPPORTED_TARGETS)
    parser.add_argument(
        "--repo",
        default=".",
        help="raíz del repositorio (default: cwd)",
    )
    parsed = parser.parse_args(args)
    return InstallRequest(
        target=parsed.target,
        repo=Path(parsed.repo).expanduser().resolve(),
    )


def validate_repo(repo: Path) -> Path:
    required = (
        repo / "flake.nix",
        repo / "inventory.nix",
        repo / "home" / "default.nix",
        repo / "modules" / "hosts" / "wsl" / "default.nix",
    )
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise HolodeckError(
            "La ruta no contiene el repositorio completo para #wsl:\n  "
            + "\n  ".join(missing)
        )
    return repo


def require_commands(command_names: tuple[str, ...]) -> None:
    missing = [name for name in command_names if shutil.which(name) is None]
    if missing:
        raise HolodeckError(
            "No se encontraron comandos requeridos: " + ", ".join(missing)
        )


def ensure_install_inputs_tracked(repo: Path) -> None:
    in_worktree = subprocess.run(
        ["git", "rev-parse", "--is-inside-work-tree"],
        cwd=repo,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if in_worktree.returncode != 0:
        return

    result = subprocess.run(
        [
            "git",
            "ls-files",
            "--others",
            "--exclude-standard",
            "--",
            *COMMON_INSTALL_INPUTS,
            *WSL_INSTALL_INPUTS,
        ],
        cwd=repo,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise HolodeckError(result.stderr.strip() or "No se pudo consultar Git.")

    untracked = result.stdout.strip()
    if untracked:
        raise HolodeckError(
            "Hay archivos de instalación sin seguimiento en Git:\n"
            f"{untracked}\n\n"
            "Agregalos o commitealos antes de instalar para que la flake "
            "pueda verlos."
        )


def check_flake(repo: Path) -> None:
    ui.heading("==> Validando la flake fijada en flake.lock")
    run(
        [
            "nix",
            "--extra-experimental-features",
            "nix-command flakes",
            "flake",
            "check",
            "path:.",
        ],
        cwd=repo,
    )


def is_wsl_environment() -> bool:
    kernel_release = Path("/proc/sys/kernel/osrelease")
    kernel_name = (
        kernel_release.read_text().lower() if kernel_release.exists() else ""
    )
    return (
        "microsoft" in kernel_name
        or "WSL_INTEROP" in os.environ
        or "WSL_DISTRO_NAME" in os.environ
    )


def install_wsl(repo: Path) -> None:
    require_commands(("git", "nix", "nixos-rebuild", "sudo"))
    if not is_wsl_environment():
        raise HolodeckError(
            "El host wsl sólo puede instalarse desde una sesión NixOS-WSL."
        )
    ensure_install_inputs_tracked(repo)

    check_flake(repo)

    ui.heading("==> Preparando la primera generación de #wsl")
    print(
        "Se usa 'boot' porque cambia el usuario predeterminado de nixos "
        f"a {DEFAULT_WSL_USER}."
    )
    run(
        [
            "sudo",
            "nixos-rebuild",
            "boot",
            "--flake",
            "path:.#wsl",
            "--option",
            "experimental-features",
            "nix-command flakes",
        ],
        cwd=repo,
    )

    print(
        f"""
La generación fue preparada. Ahora salí de NixOS-WSL:

  exit

Luego, en PowerShell de Windows, reemplazando NixOS si la distribución tiene
otro nombre:

  wsl -l -v
  wsl --terminate NixOS
  wsl -d NixOS --user root exit
  wsl --terminate NixOS
  wsl -d NixOS

La nueva sesión debería abrir como {DEFAULT_WSL_USER}@{DEFAULT_WSL_HOST_NAME}.
Las actualizaciones siguientes se aplican con:

  cd {DEFAULT_REPO_PATH}
  sudo nixos-rebuild switch --flake path:.#wsl
""".strip()
    )


def install_nixos(args: list[str]) -> None:
    request = parse_install_args(args)
    repo = validate_repo(request.repo)
    install_wsl(repo)
