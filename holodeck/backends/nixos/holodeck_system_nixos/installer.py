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
    "install-desktop.sh",
    "holodeck/core",
    "holodeck/backends/nixos",
    "modules/nixos/features/holodeck/package.nix",
)
DESKTOP_INSTALL_INPUTS = (
    "modules/hosts/desktop",
    "modules/hosts/reinstaller",
)
WSL_INSTALL_INPUTS = (
    "modules/hosts/wsl",
    "modules/home/features/shell/default.nix",
)
RUNNING_SYSTEM_MOUNTPOINTS = frozenset(
    {
        "/",
        "/boot",
        "/boot/efi",
        "/nix/.ro-store",
        "/nix/store",
    }
)
INSTALLER_MOUNTPOINTS = frozenset(
    {
        "/cdrom",
        "/iso",
    }
)
PROTECTED_MOUNTPOINTS = RUNNING_SYSTEM_MOUNTPOINTS | INSTALLER_MOUNTPOINTS
PROTECTED_MOUNT_PREFIXES = (
    "/run/archiso/",
    "/run/initramfs/",
    "/run/live/",
    "/run/miso/",
)


class _ArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise HolodeckError(f"{message}\n\n{self.format_help().rstrip()}")


@dataclass(frozen=True)
class InstallRequest:
    target: str
    repo: Path
    disk: str | None
    allow_running_system_disk: bool


@dataclass(frozen=True)
class DiskCandidate:
    stable_id: str
    resolved_path: Path
    size_bytes: int
    model: str
    serial: str
    removable: bool
    active_uses: tuple[str, ...] = ()


@dataclass(frozen=True)
class DiskUse:
    device_path: Path
    mountpoint: str


@dataclass(frozen=True)
class DiskExclusion:
    resolved_path: Path
    stable_id: str | None
    reasons: tuple[str, ...]


@dataclass(frozen=True)
class DiskDiscovery:
    candidates: tuple[DiskCandidate, ...]
    excluded: tuple[DiskExclusion, ...]


@dataclass(frozen=True)
class ValidatedDisk:
    stable_id: str
    resolved_path: Path
    active_uses: tuple[DiskUse, ...]
    contains_running_system: bool


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
    parser.add_argument(
        "--allow-running-system-disk",
        action="store_true",
        help=(
            "permite preparar mediante kexec la reinstalacion del disco que "
            "sostiene el NixOS en ejecucion; requiere --disk"
        ),
    )
    parsed = parser.parse_args(args)

    if parsed.target == "wsl" and parsed.disk:
        parser.error("--disk no se acepta para --target wsl")
    if parsed.target == "wsl" and parsed.allow_running_system_disk:
        parser.error(
            "--allow-running-system-disk no se acepta para --target wsl"
        )
    if parsed.allow_running_system_disk and not parsed.disk:
        parser.error("--allow-running-system-disk requiere --disk")

    return InstallRequest(
        target=parsed.target,
        repo=Path(parsed.repo).expanduser().resolve(),
        disk=parsed.disk,
        allow_running_system_disk=parsed.allow_running_system_disk,
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
            f"No se pudo liberar por completo {disk_label}:\n"
            f"{mounted.stdout.strip()}\n"
            "Se cancela antes de modificar el disco."
        )


def _device_tree_uses(device: dict[str, object]) -> tuple[DiskUse, ...]:
    uses: list[DiskUse] = []
    path_value = device.get("path")
    mountpoints = device.get("mountpoints")
    if isinstance(path_value, str) and isinstance(mountpoints, list):
        uses.extend(
            DiskUse(Path(path_value), mountpoint)
            for mountpoint in mountpoints
            if isinstance(mountpoint, str) and mountpoint
        )

    children = device.get("children")
    if isinstance(children, list):
        for child in children:
            if isinstance(child, dict):
                uses.extend(_device_tree_uses(child))
    return tuple(uses)


def _is_protected_disk_use(disk_use: DiskUse) -> bool:
    mountpoint = disk_use.mountpoint
    if mountpoint == "[SWAP]":
        return False
    return mountpoint in PROTECTED_MOUNTPOINTS or any(
        mountpoint.startswith(prefix)
        for prefix in PROTECTED_MOUNT_PREFIXES
    )


def _is_installer_disk_use(disk_use: DiskUse) -> bool:
    mountpoint = disk_use.mountpoint
    return mountpoint in INSTALLER_MOUNTPOINTS or any(
        mountpoint.startswith(prefix)
        for prefix in PROTECTED_MOUNT_PREFIXES
    )


def _contains_running_system(disk_uses: tuple[DiskUse, ...]) -> bool:
    return any(disk_use.mountpoint == "/" for disk_use in disk_uses)


def _require_releasable_uses(
    disk_uses: tuple[DiskUse, ...],
    disk_label: str,
) -> None:
    protected = [use for use in disk_uses if _is_protected_disk_use(use)]
    if not protected:
        return

    details = "\n".join(
        f"  {use.device_path}: {use.mountpoint}" for use in protected
    )
    raise HolodeckError(
        f"{disk_label} sostiene el sistema live, en ejecucion o un montaje "
        "protegido:\n"
        f"{details}\n"
        "Ese disco se excluye para no interrumpir el instalador."
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


def _read_lsblk_tree(resolved_disk: Path | None = None) -> list[dict[str, object]]:
    command = [
        "lsblk",
        "--json",
        "--tree",
        "--bytes",
        "--output",
        "NAME,PATH,TYPE,RM,SIZE,MODEL,SERIAL,MOUNTPOINTS",
    ]
    if resolved_disk is not None:
        command.extend(["--", str(resolved_disk)])

    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise HolodeckError(
            result.stderr.strip() or "No se pudo inspeccionar el arbol de discos."
        )

    try:
        devices = json.loads(result.stdout).get("blockdevices", [])
    except (AttributeError, json.JSONDecodeError) as exc:
        raise HolodeckError("lsblk devolvio una lista de discos invalida.") from exc
    if not isinstance(devices, list):
        raise HolodeckError("lsblk devolvio una lista de discos invalida.")
    return [device for device in devices if isinstance(device, dict)]


def inspect_desktop_disk_uses(resolved_disk: Path) -> tuple[DiskUse, ...]:
    devices = _read_lsblk_tree(resolved_disk)
    return tuple(
        disk_use
        for device in devices
        for disk_use in _device_tree_uses(device)
    )


def _protected_use_reasons(disk_uses: tuple[DiskUse, ...]) -> tuple[str, ...]:
    return tuple(
        f"{disk_use.device_path} esta montado en {disk_use.mountpoint}"
        for disk_use in disk_uses
        if _is_protected_disk_use(disk_use)
    )


def inspect_desktop_disks() -> DiskDiscovery:
    devices = _read_lsblk_tree()

    candidates: list[DiskCandidate] = []
    excluded: list[DiskExclusion] = []
    for device in devices:
        if device.get("type") != "disk":
            continue

        path_value = device.get("path")
        if not isinstance(path_value, str):
            continue
        resolved_path = Path(path_value)
        stable_id = stable_id_for_disk(resolved_path)
        disk_uses = _device_tree_uses(device)

        reasons = list(_protected_use_reasons(disk_uses))
        if stable_id is None:
            reasons.append("no tiene un ID estable en /dev/disk/by-id")

        if reasons:
            excluded.append(
                DiskExclusion(
                    resolved_path=resolved_path,
                    stable_id=stable_id,
                    reasons=tuple(reasons),
                )
            )
            continue

        candidates.append(
            DiskCandidate(
                stable_id=stable_id,
                resolved_path=resolved_path,
                size_bytes=_as_size_bytes(device.get("size")),
                model=str(device.get("model") or "").strip(),
                serial=str(device.get("serial") or "").strip(),
                removable=_is_removable(device.get("rm")),
                active_uses=tuple(
                    sorted({disk_use.mountpoint for disk_use in disk_uses})
                ),
            )
        )

    internal = [candidate for candidate in candidates if not candidate.removable]
    if internal:
        for candidate in candidates:
            if candidate.removable:
                excluded.append(
                    DiskExclusion(
                        resolved_path=candidate.resolved_path,
                        stable_id=candidate.stable_id,
                        reasons=(
                            "se omitio porque hay un disco interno seguro",
                        ),
                    )
                )
        candidates = internal
    return DiskDiscovery(
        candidates=tuple(
            sorted(candidates, key=lambda candidate: candidate.stable_id)
        ),
        excluded=tuple(
            sorted(
                excluded,
                key=lambda disk: disk.stable_id or str(disk.resolved_path),
            )
        ),
    )


def discover_desktop_disks(
    *,
    include_excluded: bool = False,
) -> list[DiskCandidate] | DiskDiscovery:
    """Return only candidates that are safe for automatic selection."""

    discovery = inspect_desktop_disks()
    if include_excluded:
        return discovery
    return list(discovery.candidates)


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
    if candidate.active_uses:
        details.append("se libera automaticamente")
    return ", ".join(details)


def _no_safe_disks_message(discovery: DiskDiscovery) -> str:
    lines = [
        "No se encontro ningun disco de destino seguro y con un ID estable "
        "en /dev/disk/by-id.",
    ]
    if discovery.excluded:
        lines.extend(("", "Discos fisicos detectados y excluidos:"))
        for disk in discovery.excluded:
            label = disk.stable_id or str(disk.resolved_path)
            lines.append(f"  {label} -> {disk.resolved_path}")
            lines.extend(f"    - {reason}" for reason in disk.reasons)
    else:
        lines.extend(("", "lsblk no detecto ningun disco fisico completo."))

    running_disks = [
        disk
        for disk in discovery.excluded
        if any(reason.endswith("montado en /") for reason in disk.reasons)
        and disk.stable_id is not None
    ]
    if running_disks:
        example = running_disks[0].stable_id
        lines.extend(
            (
                "",
                "Para reinstalar explicitamente el NixOS en ejecucion, usa:",
                "  ./install-desktop.sh "
                f"--disk {example} --allow-running-system-disk",
                "El modo avanzado arrancara un instalador efimero en RAM y "
                "pedira una confirmacion adicional.",
            )
        )
    else:
        lines.extend(
            (
                "",
                "Revisa el hardware con 'lsblk' y "
                "'ls -l /dev/disk/by-id/'.",
            )
        )
    return "\n".join(lines)


def select_desktop_disk() -> str:
    discovered = discover_desktop_disks(include_excluded=True)
    if isinstance(discovered, DiskDiscovery):
        discovery = discovered
    else:
        # Keeps selection easy to isolate in callers and older integrations.
        discovery = DiskDiscovery(tuple(discovered), ())
    candidates = list(discovery.candidates)
    if not candidates:
        raise HolodeckError(_no_safe_disks_message(discovery))

    if len(candidates) == 1:
        selected = candidates[0]
        ui.info(
            f"Disco detectado: {selected.stable_id} "
            f"({_describe_disk(selected)})"
        )
        return selected.stable_id

    ui.heading("==> Selecciona el disco de destino")
    print("Los montajes no protegidos se liberaran automaticamente:")
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


def resolve_desktop_disk(disk: str) -> Path:
    disk_path = Path(disk)
    if disk_path.parent != Path("/dev/disk/by-id") or not disk_path.name:
        raise HolodeckError(
            "Usa una ruta estable /dev/disk/by-id/*, no un nombre como "
            "/dev/nvme0n1."
        )
    if re.search(r"-part\d+$", disk_path.name):
        raise HolodeckError(
            f"{disk} apunta a una particion, no al disco completo."
        )

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

    return resolved_disk


def validate_desktop_disk_selection(
    disk: str,
    *,
    allow_running_system_disk: bool,
) -> ValidatedDisk:
    """Validate a manual or automatic choice before any destructive action."""

    resolved_disk = resolve_desktop_disk(disk)
    disk_uses = inspect_desktop_disk_uses(resolved_disk)
    protected = tuple(
        disk_use
        for disk_use in disk_uses
        if _is_protected_disk_use(disk_use)
    )
    contains_running_system = _contains_running_system(disk_uses)

    installer_uses = tuple(
        disk_use for disk_use in protected if _is_installer_disk_use(disk_use)
    )
    if installer_uses:
        details = "\n".join(
            f"  {use.device_path}: {use.mountpoint}" for use in installer_uses
        )
        raise HolodeckError(
            f"{disk} sostiene el medio o entorno de instalacion:\n"
            f"{details}\n"
            "Ni siquiera --allow-running-system-disk permite borrar el "
            "instalador que esta ejecutando este proceso."
        )

    if protected and not allow_running_system_disk:
        details = "\n".join(
            f"  {use.device_path}: {use.mountpoint}" for use in protected
        )
        hint = (
            "\n\nSi realmente queres reinstalar este sistema, repeti el "
            "comando con el mismo --disk y --allow-running-system-disk."
            if contains_running_system
            else ""
        )
        raise HolodeckError(
            f"{disk} contiene el sistema actualmente en ejecucion o un "
            f"montaje protegido:\n{details}\n"
            "Se cancela antes de modificar el disco."
            f"{hint}"
        )

    if allow_running_system_disk and not contains_running_system:
        raise HolodeckError(
            "--allow-running-system-disk solo se acepta cuando el disco "
            "seleccionado sostiene '/' del sistema actualmente en ejecucion."
        )

    return ValidatedDisk(
        stable_id=disk,
        resolved_path=resolved_disk,
        active_uses=disk_uses,
        contains_running_system=contains_running_system,
    )


def validate_desktop_disk(disk: str) -> Path:
    resolved_disk = resolve_desktop_disk(disk)
    require_unmounted_disk(resolved_disk, disk)
    return resolved_disk


def prepare_desktop_disk(resolved_disk: Path, disk_label: str) -> None:
    disk_uses = inspect_desktop_disk_uses(resolved_disk)
    _require_releasable_uses(disk_uses, disk_label)
    if not disk_uses:
        return

    ui.heading("==> Liberando automaticamente el disco de destino")

    swap_devices = sorted(
        {
            str(disk_use.device_path)
            for disk_use in disk_uses
            if disk_use.mountpoint == "[SWAP]"
        }
    )
    for device_path in swap_devices:
        ui.info(f"Desactivando swap: {device_path}")
        run(["sudo", "swapoff", "--", device_path])

    mountpoints = sorted(
        {
            disk_use.mountpoint
            for disk_use in disk_uses
            if disk_use.mountpoint != "[SWAP]"
        },
        key=lambda mountpoint: (mountpoint.count("/"), len(mountpoint)),
        reverse=True,
    )
    for mountpoint in mountpoints:
        ui.info(f"Desmontando: {mountpoint}")
        run(["sudo", "umount", "--", mountpoint])

    require_unmounted_disk(resolved_disk, disk_label)


def require_mount(mountpoint: str) -> None:
    result = subprocess.run(
        ["mountpoint", "-q", mountpoint],
        check=False,
    )
    if result.returncode != 0:
        raise HolodeckError(f"Disko no dejo {mountpoint} montado.")


def require_unmounted_mountpoint(mountpoint: str) -> None:
    result = subprocess.run(
        ["mountpoint", "-q", mountpoint],
        check=False,
    )
    if result.returncode == 0:
        raise HolodeckError(f"No se pudo desmontar automaticamente {mountpoint}.")


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


def build_reinstaller_kexec(repo: Path) -> Path:
    ui.heading("==> Construyendo el instalador efimero en RAM")
    result = subprocess.run(
        [
            "nix",
            "--extra-experimental-features",
            "nix-command flakes",
            "build",
            "--no-link",
            "--print-out-paths",
            ".#reinstaller-kexec",
        ],
        cwd=repo,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise HolodeckError(
            result.stderr.strip()
            or "No se pudo construir el instalador efimero para kexec."
        )

    output_paths = [Path(line) for line in result.stdout.splitlines() if line]
    if (
        len(output_paths) != 1
        or not output_paths[0].is_dir()
        or not (output_paths[0] / "kexec-boot").is_file()
    ):
        raise HolodeckError(
            "Nix no devolvio un unico arbol kexec valido; no se reinicio."
        )
    return output_paths[0]


def _confirm_running_system_reinstall(disk: str) -> None:
    expected = f"REINSTALAR SISTEMA EN EJECUCION {disk}"
    print("Confirmacion adicional obligatoria para abandonar el sistema activo:")
    print(expected)
    try:
        confirmation = input("> ")
    except EOFError as exc:
        raise HolodeckError(
            "No se recibio la confirmacion adicional; no se modifico el disco."
        ) from exc
    if confirmation != expected:
        raise HolodeckError(
            "Confirmacion adicional incorrecta; no se modifico el disco."
        )


def _confirm_disk_erasure(disk: str) -> None:
    expected = f"BORRAR {disk}"
    print("Escribe exactamente esta confirmacion:")
    print(expected)
    try:
        confirmation = input("> ")
    except EOFError as exc:
        raise HolodeckError(
            "No se recibio la confirmacion; no se modifico el disco."
        ) from exc
    if confirmation != expected:
        raise HolodeckError("Confirmacion incorrecta; no se modifico el disco.")


def boot_reinstaller_kexec(kexec_tree: Path, selected_disk: str) -> None:
    ui.heading("==> Arrancando el instalador efimero con kexec")
    ui.warn(
        "La sesion actual terminara ahora. Tras el arranque se volvera a "
        "pedir la confirmacion BORRAR antes de ejecutar Disko."
    )
    run(["sync"])
    run(["sudo", str(kexec_tree / "kexec-boot"), selected_disk])
    raise HolodeckError(
        "kexec devolvio el control inesperadamente; no se modifico el disco."
    )


def install_desktop(
    repo: Path,
    disk: str | None,
    allow_running_system_disk: bool = False,
) -> None:
    require_commands(
        (
            "git",
            "lsblk",
            "nix",
            "sudo",
            "sync",
        )
    )
    if not Path("/sys/firmware/efi/efivars").is_dir():
        raise HolodeckError("El instalador no fue iniciado en modo UEFI.")

    ensure_install_inputs_tracked(repo, DESKTOP_INSTALL_INPUTS)
    check_flake(repo)
    selected_disk = disk or select_desktop_disk()
    validated = validate_desktop_disk_selection(
        selected_disk,
        allow_running_system_disk=allow_running_system_disk,
    )
    resolved_disk = validated.resolved_path
    disk_uses = validated.active_uses
    kexec_tree = (
        build_reinstaller_kexec(repo)
        if validated.contains_running_system
        else None
    )
    if not validated.contains_running_system:
        require_commands(
            (
                "findmnt",
                "mountpoint",
                "nixos-enter",
                "nixos-install",
                "swapoff",
                "umount",
            )
        )

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
    if disk_uses:
        print()
        if validated.contains_running_system:
            print("Usos protegidos detectados en el sistema actual:")
        else:
            print("El proceso liberara automaticamente estos usos:")
        for disk_use in disk_uses:
            print(f"  {disk_use.device_path}: {disk_use.mountpoint}")
    print()
    if validated.contains_running_system:
        ui.warn(
            "PELIGRO: el disco seleccionado contiene '/' y el NixOS que "
            "esta ejecutando este instalador."
        )
        print(
            "No se intentara desmontar el sistema activo. Primero se arrancara "
            "un NixOS efimero enteramente en RAM mediante kexec."
        )
        print()
        _confirm_running_system_reinstall(selected_disk)
        print()
    _confirm_disk_erasure(selected_disk)

    pre_release = validate_desktop_disk_selection(
        selected_disk,
        allow_running_system_disk=allow_running_system_disk,
    )
    if pre_release.resolved_path != resolved_disk:
        raise HolodeckError(
            "El ID seleccionado ahora apunta a otro disco; no se modifico nada."
        )

    if pre_release.contains_running_system:
        if kexec_tree is None:
            raise HolodeckError(
                "No se preparo el entorno efimero; no se modifico el disco."
            )
        boot_reinstaller_kexec(kexec_tree, selected_disk)
        return

    prepare_desktop_disk(pre_release.resolved_path, selected_disk)
    revalidated_disk = validate_desktop_disk(selected_disk)
    if revalidated_disk != resolved_disk:
        raise HolodeckError(
            "El ID seleccionado cambio durante la preparacion; "
            "no se modifico el disco."
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

    ui.heading("==> Sincronizando y desmontando la instalacion")
    run(["sync"])
    run(["sudo", "umount", "-R", "--", "/mnt"])
    require_unmounted_mountpoint("/mnt")

    print(
        """
Instalacion terminada y desmontada. Verifica que no haya errores y reinicia:

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
        install_desktop(
            repo,
            request.disk,
            request.allow_running_system_disk,
        )
        return
    install_wsl(repo)
