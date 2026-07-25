"""NixOS-specific installation backend for Holodeck."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import stat
import subprocess
from dataclasses import dataclass
from pathlib import Path

from holodeck.errors import HolodeckError
from holodeck.process import run
from holodeck.ui import ui


SUPPORTED_TARGETS = ("desktop", "wsl")
EXPECTED_WSL_REPO = Path("/home/avivaldelli/projects/personal/nixos-config")
COMMON_INSTALL_INPUTS = (
    "flake.nix",
    "flake.lock",
    "install.sh",
    "holodeck/core",
    "holodeck/backends/nixos",
    "modules/nixos/features/holodeck/package.nix",
)
DESKTOP_INSTALL_INPUTS = (
    "modules/hosts/desktop",
)
WSL_INSTALL_INPUTS = (
    "modules/hosts/wsl",
    "modules/home/features/shell/default.nix",
)


class _ArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise HolodeckError(f"{message}\n\n{self.format_help().rstrip()}")


@dataclass(frozen=True)
class InstallRequest:
    target: str
    repo: Path
    disk: str | None


@dataclass(frozen=True)
class DiskCandidate:
    stable_id: str
    resolved_path: Path
    size_bytes: int
    model: str
    serial: str
    removable: bool


def parse_install_args(args: list[str]) -> InstallRequest:
    parser = _ArgumentParser(
        prog="holodeck-system-nixos install",
        description="Instala un target NixOS declarado por este repositorio.",
    )
    parser.add_argument("--target", required=True, choices=SUPPORTED_TARGETS)
    parser.add_argument(
        "--repo",
        default=".",
        help="raiz del repositorio (default: cwd)",
    )
    parser.add_argument(
        "--disk",
        help=(
            "override avanzado /dev/disk/by-id/*; desktop lo detecta "
            "automaticamente si se omite"
        ),
    )
    parsed = parser.parse_args(args)

    if parsed.target == "wsl" and parsed.disk:
        parser.error("--disk no se acepta para --target wsl")

    return InstallRequest(
        target=parsed.target,
        repo=Path(parsed.repo).expanduser().resolve(),
        disk=parsed.disk,
    )


def validate_repo(repo: Path, target: str) -> Path:
    required = (
        repo / "flake.nix",
        repo / "modules" / "hosts" / target / "default.nix",
    )
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise HolodeckError(
            "La ruta no contiene el repositorio completo para "
            f"#{target}:\n  " + "\n  ".join(missing)
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
    target_inputs: tuple[str, ...],
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
            *target_inputs,
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


def _device_tree_has_mounts(device: dict[str, object]) -> bool:
    mountpoints = device.get("mountpoints")
    if isinstance(mountpoints, list) and any(mountpoints):
        return True

    children = device.get("children")
    if not isinstance(children, list):
        return False
    return any(
        _device_tree_has_mounts(child)
        for child in children
        if isinstance(child, dict)
    )


def _stable_id_priority(path: Path) -> tuple[int, str]:
    prefixes = (
        "wwn-",
        "nvme-eui.",
        "nvme-uuid.",
        "nvme-",
        "ata-",
        "scsi-",
        "virtio-",
        "usb-",
    )
    for priority, prefix in enumerate(prefixes):
        if path.name.startswith(prefix):
            return priority, path.name
    return len(prefixes), path.name


def stable_id_for_disk(
    resolved_disk: Path,
    by_id_dir: Path = Path("/dev/disk/by-id"),
) -> str | None:
    if not by_id_dir.is_dir():
        return None

    matches: list[Path] = []
    for candidate in by_id_dir.iterdir():
        if re.search(r"-part\d+$", candidate.name):
            continue
        try:
            if candidate.resolve(strict=True) == resolved_disk:
                matches.append(candidate)
        except (FileNotFoundError, OSError):
            continue

    if not matches:
        return None
    return str(min(matches, key=_stable_id_priority))


def _is_removable(value: object) -> bool:
    return str(value).lower() in {"1", "true", "yes"}


def _as_size_bytes(value: object) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def discover_desktop_disks() -> list[DiskCandidate]:
    result = subprocess.run(
        [
            "lsblk",
            "--json",
            "--bytes",
            "--output",
            "PATH,TYPE,RM,SIZE,MODEL,SERIAL,MOUNTPOINTS",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise HolodeckError(
            result.stderr.strip() or "No se pudieron detectar los discos."
        )

    try:
        devices = json.loads(result.stdout).get("blockdevices", [])
    except (AttributeError, json.JSONDecodeError) as exc:
        raise HolodeckError("lsblk devolvio una lista de discos invalida.") from exc

    candidates: list[DiskCandidate] = []
    for device in devices:
        if not isinstance(device, dict) or device.get("type") != "disk":
            continue
        if _device_tree_has_mounts(device):
            continue

        path_value = device.get("path")
        if not isinstance(path_value, str):
            continue
        resolved_path = Path(path_value)
        stable_id = stable_id_for_disk(resolved_path)
        if stable_id is None:
            continue

        candidates.append(
            DiskCandidate(
                stable_id=stable_id,
                resolved_path=resolved_path,
                size_bytes=_as_size_bytes(device.get("size")),
                model=str(device.get("model") or "").strip(),
                serial=str(device.get("serial") or "").strip(),
                removable=_is_removable(device.get("rm")),
            )
        )

    internal = [candidate for candidate in candidates if not candidate.removable]
    if internal:
        candidates = internal
    return sorted(candidates, key=lambda candidate: candidate.stable_id)


def _format_size(size_bytes: int) -> str:
    if size_bytes <= 0:
        return "tamano desconocido"
    size = float(size_bytes)
    units = ("B", "KiB", "MiB", "GiB", "TiB", "PiB")
    for unit in units:
        if size < 1024 or unit == units[-1]:
            return f"{size:.0f} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{size_bytes} B"


def _describe_disk(candidate: DiskCandidate) -> str:
    details = [_format_size(candidate.size_bytes)]
    if candidate.model:
        details.append(candidate.model)
    if candidate.serial:
        details.append(f"serial {candidate.serial}")
    if candidate.removable:
        details.append("removible")
    return ", ".join(details)


def select_desktop_disk() -> str:
    candidates = discover_desktop_disks()
    if not candidates:
        raise HolodeckError(
            "No se encontro ningun disco completo, sin montajes y con un ID "
            "estable en /dev/disk/by-id.\n"
            "Revisa el hardware con 'lsblk' y 'ls -l /dev/disk/by-id/'."
        )

    if len(candidates) == 1:
        selected = candidates[0]
        ui.info(
            f"Disco detectado: {selected.stable_id} "
            f"({_describe_disk(selected)})"
        )
        return selected.stable_id

    ui.heading("==> Selecciona el disco de destino")
    print("Solo se muestran discos completos y sin montajes activos:")
    for index, candidate in enumerate(candidates, start=1):
        print(f"  {index}) {candidate.stable_id}")
        print(f"     {_describe_disk(candidate)}")

    try:
        selection = input(f"Opcion [1-{len(candidates)}]: ").strip()
        selected_index = int(selection) - 1
        if selected_index < 0:
            raise IndexError
        selected = candidates[selected_index]
    except (EOFError, ValueError, IndexError) as exc:
        raise HolodeckError(
            "Seleccion de disco invalida. Tambien podes usar el override "
            "--disk /dev/disk/by-id/ID."
        ) from exc

    ui.info(f"Disco seleccionado: {selected.stable_id}")
    return selected.stable_id


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


def install_desktop(repo: Path, disk: str | None) -> None:
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

    ensure_install_inputs_tracked(repo, DESKTOP_INSTALL_INPUTS)
    check_flake(repo)
    selected_disk = disk or select_desktop_disk()
    resolved_disk = validate_desktop_disk(selected_disk)

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
    expected_confirmation = f"BORRAR {selected_disk}"
    print("Escribe exactamente esta confirmacion:")
    print(expected_confirmation)
    confirmation = input("> ")
    if confirmation != expected_confirmation:
        raise HolodeckError("Confirmacion incorrecta; no se modifico el disco.")

    revalidated_disk = validate_desktop_disk(selected_disk)
    if revalidated_disk != resolved_disk:
        raise HolodeckError(
            "El ID seleccionado ahora apunta a otro disco; no se modifico nada."
        )

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
            selected_disk,
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


def install_nixos(args: list[str]) -> None:
    request = parse_install_args(args)
    repo = validate_repo(request.repo, request.target)

    if request.target == "desktop":
        install_desktop(repo, request.disk)
        return
    install_wsl(repo)
