from __future__ import annotations

import configparser
import os
import shlex
import shutil
import subprocess
from collections.abc import Callable, Mapping
from pathlib import Path
from typing import Any, TextIO

from .errors import ConfigCtlError

Runner = Callable[..., subprocess.CompletedProcess[str]]
Input = Callable[[str], str]
Which = Callable[..., str | None]


ACTION_COMMANDS: dict[str, tuple[str, ...]] = {
    "holodeck-setup": ("holodeck", "setup"),
    "holodeck-doctor": ("holodeck", "doctor"),
    "github-setup": ("holodeck", "github"),
    "gitlab-setup": ("holodeck", "gitlab"),
    "aws-configure": ("aws", "configure", "sso"),
    "windows-up": ("windowsvm", "up"),
    "windows-status": ("windowsvm", "status"),
    "windows-rdp": ("windowsvm", "rdp"),
    "windows-web": ("windowsvm", "web"),
    "windows-logs": ("windowsvm", "logs"),
    "windows-down": ("windowsvm", "down"),
}

AWS_PROFILE_ACTIONS = {
    "aws-login": ("sso", "login"),
    "aws-identity": ("sts", "get-caller-identity"),
}

ALL_ACTIONS = tuple((*ACTION_COMMANDS.keys(), *AWS_PROFILE_ACTIONS.keys()))


def _home(environ: Mapping[str, str]) -> Path:
    return Path(environ.get("HOME", str(Path.home()))).expanduser()


def _config_home(environ: Mapping[str, str]) -> Path:
    return Path(environ.get("XDG_CONFIG_HOME", str(_home(environ) / ".config"))).expanduser()


def _command_path(name: str, environ: Mapping[str, str], which: Which) -> str | None:
    try:
        return which(name, path=environ.get("PATH"))
    except TypeError:
        return which(name)


def _parse_profile_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return values

    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        if line.startswith("export "):
            line = line[len("export ") :]
        key, raw_value = line.split("=", 1)
        if key not in {"HOLODECK_PROFILE", "HOLODECK_PROVIDER", "HOLODECK_HOST"}:
            continue
        try:
            parts = shlex.split(raw_value)
        except ValueError:
            continue
        values[key] = parts[0] if parts else ""
    return values


def provider_profiles(environ: Mapping[str, str]) -> list[dict[str, str]]:
    directory = _config_home(environ) / "holodeck" / "profiles"
    if not directory.is_dir():
        return []

    result: list[dict[str, str]] = []
    for path in sorted(directory.glob("*.env")):
        values = _parse_profile_file(path)
        provider = values.get("HOLODECK_PROVIDER", "")
        if provider not in {"github", "gitlab"}:
            continue
        result.append(
            {
                "host": values.get("HOLODECK_HOST", ""),
                "name": values.get("HOLODECK_PROFILE", path.stem),
                "provider": provider,
            }
        )
    return result


def aws_profiles(environ: Mapping[str, str]) -> list[str]:
    path = Path(environ.get("AWS_CONFIG_FILE", str(_home(environ) / ".aws" / "config")))
    parser = configparser.RawConfigParser()
    try:
        with path.open(encoding="utf-8") as handle:
            parser.read_file(handle)
    except (OSError, configparser.Error):
        return []

    names: set[str] = set()
    for section in parser.sections():
        if section == "default":
            names.add("default")
        elif section.startswith("profile "):
            name = section[len("profile ") :].strip()
            if name:
                names.add(name)
    return sorted(names)


def integration_status(
    environ: Mapping[str, str], *, which: Which = shutil.which
) -> dict[str, Any]:
    profiles = provider_profiles(environ)
    github = [profile for profile in profiles if profile["provider"] == "github"]
    gitlab = [profile for profile in profiles if profile["provider"] == "gitlab"]
    aws = aws_profiles(environ)
    holodeck_available = _command_path("holodeck", environ, which) is not None

    return {
        "aws": {
            "available": _command_path("aws", environ, which) is not None,
            "configured": bool(aws),
            "profiles": aws,
        },
        "github": {
            "available": holodeck_available
            and _command_path("gh", environ, which) is not None,
            "configured": bool(github),
            "profiles": github,
        },
        "gitlab": {
            "available": holodeck_available
            and _command_path("glab", environ, which) is not None,
            "configured": bool(gitlab),
            "profiles": gitlab,
        },
        "windowsVm": {
            "available": _command_path("windowsvm", environ, which) is not None,
            "configured": _command_path("windowsvm", environ, which) is not None,
        },
    }


def _select_aws_profile(
    environ: Mapping[str, str], *, input_fn: Input, stdout: TextIO
) -> str:
    profiles = aws_profiles(environ)
    if not profiles:
        raise ConfigCtlError(
            "missing-aws-profile",
            "no hay perfiles AWS; ejecutá primero `holodeckctl action aws-configure`",
        )
    if len(profiles) == 1:
        stdout.write(f"Perfil AWS: {profiles[0]}\n")
        return profiles[0]

    stdout.write("Perfiles AWS disponibles:\n")
    for index, profile in enumerate(profiles, start=1):
        stdout.write(f"  {index}) {profile}\n")
    selection = input_fn("Elegí un perfil AWS: ").strip()
    if not selection.isdigit():
        raise ConfigCtlError("invalid-selection", "la selección AWS debe ser un número")
    index = int(selection)
    if index < 1 or index > len(profiles):
        raise ConfigCtlError("invalid-selection", "perfil AWS fuera de rango")
    return profiles[index - 1]


def execute_action(
    action: str,
    environ: Mapping[str, str],
    *,
    rdp_display_mode: str = "half",
    runner: Runner = subprocess.run,
    input_fn: Input = input,
    stdout: TextIO,
    which: Which = shutil.which,
) -> dict[str, Any]:
    if action in ACTION_COMMANDS:
        argv = list(ACTION_COMMANDS[action])
        if action in {"windows-up", "windows-rdp"}:
            if rdp_display_mode not in {"half", "fullscreen"}:
                raise ConfigCtlError(
                    "invalid-rdp-display-mode",
                    "el modo RDP debe ser half o fullscreen",
                )
            argv.append(rdp_display_mode)
    elif action in AWS_PROFILE_ACTIONS:
        profile = _select_aws_profile(environ, input_fn=input_fn, stdout=stdout)
        argv = ["aws", *AWS_PROFILE_ACTIONS[action], "--profile", profile]
    else:
        raise ConfigCtlError("unknown-action", f"acción no permitida: {action}")

    executable = _command_path(argv[0], environ, which)
    if executable is None:
        raise ConfigCtlError(
            "feature-unavailable",
            f"la integración requiere `{argv[0]}`; aplicá primero la configuración correspondiente",
        )

    argv[0] = executable
    try:
        completed = runner(argv, check=False, shell=False, text=True)
    except OSError as exc:
        raise ConfigCtlError(
            "exec-failed", f"no se pudo iniciar {argv[0]}: {exc}", exit_code=1
        ) from exc

    return {
        "action": action,
        "argv": argv,
        "command": "action",
        "exitCode": completed.returncode,
        "ok": completed.returncode == 0,
    }
