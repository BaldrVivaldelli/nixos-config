from __future__ import annotations

import configparser
import os
import re
import shlex
import shutil
import subprocess
from collections.abc import Callable, Mapping
from pathlib import Path
from typing import Any, TextIO

from .aws_sso import (
    SsoClientFactory,
    aws_alias_profiles,
    default_sso_client_factory,
    sync_aws_sso,
)
from .errors import ConfigCtlError

Runner = Callable[..., subprocess.CompletedProcess[str]]
Input = Callable[[str], str]
Which = Callable[..., str | None]
GITLAB_HOST_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$")


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

AWS_SYNC_ACTIONS = ("aws-sync",)

AWS_PROFILE_ACTIONS = {
    "aws-login": ("sso", "login"),
    "aws-identity": ("sts", "get-caller-identity"),
}

ALL_ACTIONS = tuple(
    (*ACTION_COMMANDS.keys(), *AWS_PROFILE_ACTIONS.keys(), *AWS_SYNC_ACTIONS)
)


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


def gitlab_auth_state(
    environ: Mapping[str, str], executable: str | None
) -> tuple[bool, list[str]]:
    """Ask glab whether it has a valid session without exposing credentials."""
    if executable is None:
        return False, []

    host = ""
    try:
        configured_host = subprocess.run(
            [executable, "config", "get", "host"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
            shell=False,
            text=True,
            env=dict(environ),
        )
        candidate = configured_host.stdout.strip().lower()
        if configured_host.returncode == 0 and GITLAB_HOST_RE.fullmatch(candidate):
            host = candidate
    except OSError:
        pass

    status_args = [executable, "auth", "status"]
    status_args.extend(["--hostname", host] if host else ["--all"])
    try:
        status = subprocess.run(
            status_args,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
            shell=False,
            text=True,
            env=dict(environ),
        )
    except OSError:
        return False, []
    if status.returncode != 0:
        return False, []
    return True, [host] if host else []


def integration_status(
    environ: Mapping[str, str], *, which: Which = shutil.which
) -> dict[str, Any]:
    profiles = provider_profiles(environ)
    github = [profile for profile in profiles if profile["provider"] == "github"]
    aws = aws_profiles(environ)
    managed_assignments = aws_alias_profiles(environ)
    holodeck_available = _command_path("holodeck", environ, which) is not None
    glab = _command_path("glab", environ, which)
    gitlab_authenticated, gitlab_hosts = gitlab_auth_state(environ, glab)

    return {
        "aws": {
            "aliases": managed_assignments,
            "available": _command_path("aws", environ, which) is not None,
            "configured": bool(managed_assignments or aws),
            "pendingRegionCount": sum(
                1
                for assignment in managed_assignments
                if assignment.get("pending") is True
            ),
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
            and glab is not None,
            "configured": gitlab_authenticated,
            "hosts": gitlab_hosts,
            "profiles": [],
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
            "no hay perfiles AWS; ejecutá primero `holodeckctl action aws-sync`",
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
    aws_client_factory: SsoClientFactory = default_sso_client_factory,
) -> dict[str, Any]:
    if action in AWS_SYNC_ACTIONS:
        return sync_aws_sso(
            environ,
            runner=runner,
            input_fn=input_fn,
            stdout=stdout,
            which=which,
            client_factory=aws_client_factory,
        )

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

    result = {
        "action": action,
        "argv": argv,
        "command": "action",
        "exitCode": completed.returncode,
        "ok": completed.returncode == 0,
    }

    if action == "holodeck-setup" and result["ok"]:
        answer = input_fn("¿Configurar o sincronizar AWS SSO ahora? [S/n]: ").strip().lower()
        if answer not in {"n", "no"}:
            aws_result = sync_aws_sso(
                environ,
                runner=runner,
                input_fn=input_fn,
                stdout=stdout,
                which=which,
                client_factory=aws_client_factory,
            )
            aws_result["action"] = action
            aws_result["components"] = ["git", "aws"]
            return aws_result

    return result
