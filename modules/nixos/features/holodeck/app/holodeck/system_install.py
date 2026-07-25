from __future__ import annotations

import argparse
import os
import shutil
import stat
import subprocess
from dataclasses import dataclass
from pathlib import Path

from .errors import HolodeckError
from .process import run
from .ui import ui


SUPPORTED_HOSTS = ("desktop", "wsl")
EXPECTED_WSL_REPO = Path("/home/avivaldelli/projects/personal/nixos-config")
COMMON_INSTALL_INPUTS = (
    "flake.nix",
    "flake.lock",
    "modules/nixos/features/holodeck",
)
DESKTOP_INSTALL_INPUTS = (
    "install-desktop.sh",
    "modules/hosts/desktop",
)
WSL_INSTALL_INPUTS = (
    "install-wsl.sh",
    "bootstrap-wsl.sh",
    "modules/hosts/wsl",
    "modules/home/features/shell/default.nix",
)


class _ArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise HolodeckError(f"{message}\n\n{self.format_help().rstrip()}")


@dataclass(frozen=True)
class InstallRequest:
    host: str
    repo: Path
    disk: str | None


def parse_install_args(args: list[str]) -> InstallRequest:
    parser = _ArgumentParser(
        prog="holodeck system install",
        description="Instala una plataforma declarada por este repositorio.",
    )
    parser.add_argument("--host", required=True, choices=SUPPORTED_HOSTS)
    parser.add_argument("--repo", default=".", help="raiz del repositorio (default: cwd)")
    parser.add_argument(
        "--disk",
        help="disco fisico estable /dev/disk/by-id/*; requerido para desktop",
    )
    parsed = parser.parse_args(args)

    if parsed.host == "desktop" and not parsed.disk:
        parser.error("--disk es obligatorio para --host desktop")
    if parsed.host == "wsl" and parsed.disk:
        parser.error("--disk no se acepta para --host wsl")

    return InstallRequest(
        host=parsed.host,
        repo=Path(parsed.repo).expanduser().resolve(),
        disk=parsed.disk,
    )


def validate_repo(repo: Path, host: str) -> Path:
    required = (
        repo / "flake.nix",
        repo / "modules" / "hosts" / host / "default.nix",
    )
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise HolodeckError(
            "La ruta no contiene el repositorio completo para "
            f"#{host}:\n  " + "\n  ".join(missing)
        )
    return repo


def require_commands(command_names: tuple[str, ...]) -> None:
    missing = [name for name in command_names if shutil.which(name) is None]
    if missing:
        raise HolodeckError(
            "No se encontraron comandos requeridos: " + ", ".join(missing)
        )


def ensure_install_inputs_tracked(
    repo: Path,
    host_inputs: tuple[str, ...],
) -> None:
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
            *host_inputs,
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
            "Hay archivos de instalacion sin seguimiento en Git:\n"
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
        ],
        cwd=repo,
    )


def require_unmounted_disk(resolved_disk: Path, disk_label: str) -> None:
    mounted = subprocess.run(
        ["lsblk", "-nrpo", "MOUNTPOINTS", "--", str(resolved_disk)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if mounted.returncode != 0:
        raise HolodeckError(
            mounted.stderr.strip()
            or f"No se pudieron revisar montajes en {disk_label}."
        )
    if mounted.stdout.strip():
        raise HolodeckError(
            f"{disk_label} o alguna de sus particiones esta montada:\n"
            f"{mounted.stdout.strip()}\n"
            "Desmontala explicitamente antes de continuar."
        )


def validate_desktop_disk(disk: str) -> Path:
    if not disk.startswith("/dev/disk/by-id/"):
        raise HolodeckError(
            "Usa una ruta estable /dev/disk/by-id/*, no un nombre como "
            "/dev/nvme0n1."
        )

    disk_path = Path(disk)
    try:
        resolved_disk = disk_path.resolve(strict=True)
        mode = resolved_disk.stat().st_mode
    except FileNotFoundError as exc:
        raise HolodeckError(
            f"El dispositivo no existe o no se puede resolver: {disk}"
        ) from exc

    if not stat.S_ISBLK(mode):
        raise HolodeckError(f"{disk} no apunta a un dispositivo de bloques.")

    result = subprocess.run(
        ["lsblk", "-ndo", "TYPE", "--", str(resolved_disk)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise HolodeckError(result.stderr.strip() or f"No se pudo leer {disk}.")
    if result.stdout.strip() != "disk":
        raise HolodeckError(f"{disk} no apunta a un disco fisico completo.")

    require_unmounted_disk(resolved_disk, disk)
    return resolved_disk


def require_mount(mountpoint: str) -> None:
    result = subprocess.run(
        ["mountpoint", "-q", mountpoint],
        check=False,
    )
    if result.returncode != 0:
        raise HolodeckError(f"Disko no dejo {mountpoint} montado.")


def require_vfat_boot() -> None:
    result = subprocess.run(
        ["findmnt", "-nro", "FSTYPE", "--mountpoint", "/mnt/boot"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0 or result.stdout.strip() != "vfat":
        raise HolodeckError("/mnt/boot no es una particion vfat.")


def install_desktop(repo: Path, disk: str) -> None:
    require_commands(
        (
            "findmnt",
            "git",
            "lsblk",
            "mountpoint",
            "nix",
            "nixos-enter",
            "nixos-install",
            "sudo",
        )
    )
    if not Path("/sys/firmware/efi/efivars").is_dir():
        raise HolodeckError("El instalador no fue iniciado en modo UEFI.")

    resolved_disk = validate_desktop_disk(disk)
    ensure_install_inputs_tracked(repo, DESKTOP_INSTALL_INPUTS)
    check_flake(repo)

    print()
    ui.warn("Este proceso borrara por completo el siguiente disco:")
    run(
        [
            "lsblk",
            "-o",
            "NAME,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINTS",
            "--",
            str(resolved_disk),
        ]
    )
    print()
    expected_confirmation = f"BORRAR {disk}"
    print("Escribe exactamente esta confirmacion:")
    print(expected_confirmation)
    confirmation = input("> ")
    if confirmation != expected_confirmation:
        raise HolodeckError("Confirmacion incorrecta; no se modifico el disco.")

    ui.heading("==> Particionando, cifrando y montando con Disko")
    run(
        [
            "sudo",
            "nix",
            "--extra-experimental-features",
            "nix-command flakes",
            "run",
            ".#disko",
            "--",
            "--mode",
            "destroy,format,mount",
            "--argstr",
            "device",
            disk,
            "modules/hosts/desktop/disko.nix",
        ],
        cwd=repo,
    )

    require_mount("/mnt")
    require_mount("/mnt/boot")
    require_vfat_boot()

    ui.heading("==> Instalando #desktop")
    run(["sudo", "nixos-install", "--flake", ".#desktop"], cwd=repo)

    ui.heading("==> Configurando la contrasena de avivaldelli")
    run(
        [
            "sudo",
            "nixos-enter",
            "--root",
            "/mnt",
            "-c",
            "passwd avivaldelli",
        ]
    )

    print(
        """
Instalacion terminada. Verifica que no haya errores, desmonta y reinicia:

  sudo umount -R /mnt
  sudo reboot

Retira el medio de instalacion durante el reinicio. Despues de iniciar sesion
como avivaldelli, completa el estado personal sin sudo:

  holodeck setup
""".strip()
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
            "El host wsl solo puede instalarse desde una sesion NixOS-WSL."
        )
    ensure_install_inputs_tracked(repo, WSL_INSTALL_INPUTS)

    if repo != EXPECTED_WSL_REPO:
        ui.warn(f"El repo esta en {repo}.")
        print(
            "Los aliases nixswitch/nixbuild esperan:\n"
            f"  {EXPECTED_WSL_REPO}\n\n"
            "La primera instalacion puede continuar, pero conviene mover el "
            "repo a esa ruta."
        )
        print()

    check_flake(repo)

    ui.heading("==> Preparando la primera generacion de #wsl")
    print(
        "Se usa 'boot' porque cambia el usuario predeterminado de nixos "
        "a avivaldelli."
    )
    run(
        [
            "sudo",
            "nixos-rebuild",
            "boot",
            "--flake",
            ".#wsl",
            "--option",
            "experimental-features",
            "nix-command flakes",
        ],
        cwd=repo,
    )

    print(
        """
La generacion fue preparada. Ahora sali de NixOS-WSL:

  exit

Luego, en PowerShell de Windows, reemplazando NixOS si la distribucion tiene
otro nombre:

  wsl -l -v
  wsl --terminate NixOS
  wsl -d NixOS --user root exit
  wsl --terminate NixOS
  wsl -d NixOS

La nueva sesion deberia abrir como avivaldelli@nixos-wsl. Completa el estado
personal sin sudo:

  holodeck setup

Las actualizaciones siguientes se aplican con:

  cd ~/projects/personal/nixos-config
  nixswitch
""".strip()
    )


def install_system(args: list[str]) -> None:
    request = parse_install_args(args)
    repo = validate_repo(request.repo, request.host)

    if request.host == "desktop":
        assert request.disk is not None
        install_desktop(repo, request.disk)
        return
    install_wsl(repo)
