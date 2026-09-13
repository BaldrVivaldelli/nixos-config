from __future__ import annotations

import configparser
import json
import os
import re
import shlex
import shutil
import stat
import subprocess
import tempfile
import time
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
RDP_REQUEST_FILENAME = "holodeck-control-windows-rdp.json"
RDP_REQUEST_MAX_BYTES = 8192
RDP_REQUEST_MAX_AGE_MS = 30_000
WINDOWS_CREDENTIAL_MAX_BYTES = 8192


ACTION_COMMANDS: dict[str, tuple[str, ...]] = {
    "holodeck-setup": ("holodeck", "setup"),
    "holodeck-doctor": ("holodeck", "doctor"),
    "github-setup": ("holodeck", "github"),
    "gitlab-setup": ("holodeck", "gitlab"),
    "aws-configure": ("aws", "configure", "sso"),
    "windows-up": ("windowsvm", "up"),
    "windows-status": ("windowsvm", "status"),
    "windows-rdp": ("windowsvm", "rdp"),
    "windows-unlock": ("windowsvm", "unlock"),
    "windows-password-reset": ("windowsvm", "password-reset"),
    "windows-wipe": ("windowsvm", "wipe"),
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


def _aws_profile_path(environ: Mapping[str, str]) -> Path:
    root = environ.get("XDG_STATE_HOME") or str(_home(environ) / ".local" / "state")
    return Path(root) / "aws" / "last-profile"


def active_aws_profile(environ: Mapping[str, str], profiles: list[str]) -> str:
    for key in ("AWS_PROFILE", "AWS_DEFAULT_PROFILE"):
        if environ.get(key) in profiles:
            return environ[key]
    try:
        with _aws_profile_path(environ).open(encoding="utf-8") as handle:
            profile = handle.read(4096).strip()
    except (OSError, UnicodeError):
        return ""
    return profile if profile in profiles else ""


def remember_aws_profile(environ: Mapping[str, str], profile: str) -> None:
    if profile not in aws_profiles(environ) or "\n" in profile or "\r" in profile:
        raise ConfigCtlError("invalid-aws-profile", "el perfil AWS ya no está disponible")
    path = _aws_profile_path(environ)
    try:
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        descriptor, temporary = tempfile.mkstemp(prefix=".last-profile.", dir=path.parent)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                handle.write(profile + "\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, path)
        finally:
            Path(temporary).unlink(missing_ok=True)
    except OSError as exc:
        raise ConfigCtlError("aws-profile-write-failed", "no se pudo recordar el perfil AWS") from exc


def select_aws_profile_request(environ: Mapping[str, str]) -> dict[str, Any]:
    root = Path(environ.get("NOCTALIA_STATE_HOME") or environ.get("XDG_STATE_HOME")
                or str(_home(environ) / ".local" / "state"))
    path = root / "noctalia/plugins/data/holodeck/control/aws-profile-request.json"
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(descriptor, "r", encoding="utf-8") as handle:
            info = os.fstat(handle.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > 8192:
                raise ValueError("invalid request file")
            request = json.loads(handle.read(8193))
    except (OSError, ValueError, UnicodeError) as exc:
        raise ConfigCtlError("invalid-aws-profile-request", "no se pudo leer la selección AWS") from exc
    finally:
        path.unlink(missing_ok=True)
    if (not isinstance(request, dict) or set(request) != {"schemaVersion", "profile"}
            or type(request["schemaVersion"]) is not int or request["schemaVersion"] != 1
            or not isinstance(request["profile"], str)):
        raise ConfigCtlError("invalid-aws-profile-request", "la selección AWS no es válida")
    remember_aws_profile(environ, request["profile"])
    return {"ok": True, "command": "aws-profile-select", "activeProfile": request["profile"]}


def _consume_rdp_request(environ: Mapping[str, str]) -> dict[str, str] | None:
    runtime_value = environ.get("XDG_RUNTIME_DIR", "")
    if not runtime_value:
        return None

    runtime_dir = Path(runtime_value)
    request_path = runtime_dir / RDP_REQUEST_FILENAME
    if not request_path.exists():
        return None

    try:
        runtime_status = runtime_dir.stat(follow_symlinks=False)
    except OSError as exc:
        raise ConfigCtlError(
            "invalid-rdp-request", "no se pudo validar XDG_RUNTIME_DIR"
        ) from exc
    if (
        not runtime_dir.is_absolute()
        or not stat.S_ISDIR(runtime_status.st_mode)
        or runtime_status.st_uid != os.getuid()
        or runtime_status.st_mode & 0o077
    ):
        raise ConfigCtlError(
            "invalid-rdp-request",
            "XDG_RUNTIME_DIR no es un directorio privado del usuario actual",
        )

    descriptor = -1
    try:
        descriptor = os.open(
            request_path,
            os.O_RDONLY | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0),
        )
        request_status = os.fstat(descriptor)
        if (
            not stat.S_ISREG(request_status.st_mode)
            or request_status.st_uid != os.getuid()
            or request_status.st_size > RDP_REQUEST_MAX_BYTES
        ):
            raise ConfigCtlError(
                "invalid-rdp-request", "la solicitud RDP efímera no es segura"
            )
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "rb") as request_file:
            descriptor = -1
            raw = request_file.read(RDP_REQUEST_MAX_BYTES + 1)
    except ConfigCtlError:
        raise
    except OSError as exc:
        raise ConfigCtlError(
            "invalid-rdp-request", "no se pudo leer la solicitud RDP efímera"
        ) from exc
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            request_path.unlink()
        except FileNotFoundError:
            pass
        except OSError:
            pass

    if len(raw) > RDP_REQUEST_MAX_BYTES:
        raise ConfigCtlError(
            "invalid-rdp-request", "la solicitud RDP efímera es demasiado grande"
        )
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ConfigCtlError(
            "invalid-rdp-request", "la solicitud RDP efímera no es JSON válido"
        ) from exc

    if not isinstance(payload, dict) or set(payload) != {
        "schemaVersion",
        "createdAtMs",
        "username",
        "password",
    }:
        raise ConfigCtlError(
            "invalid-rdp-request", "la solicitud RDP efímera tiene campos inválidos"
        )
    created_at = payload["createdAtMs"]
    if isinstance(created_at, bool) or not isinstance(created_at, (int, float)):
        raise ConfigCtlError(
            "invalid-rdp-request", "la solicitud RDP efímera no tiene una fecha válida"
        )
    now_ms = time.time_ns() // 1_000_000
    if (
        isinstance(payload["schemaVersion"], bool)
        or payload["schemaVersion"] != 1
        or not (-5_000 <= now_ms - created_at <= RDP_REQUEST_MAX_AGE_MS)
    ):
        raise ConfigCtlError(
            "invalid-rdp-request", "la solicitud RDP efímera venció"
        )

    username = payload["username"]
    password = payload["password"]
    if (
        not isinstance(username, str)
        or not username
        or len(username) > 128
        or username != username.strip()
        or any(character in username for character in ("\0", "\r", "\n"))
    ):
        raise ConfigCtlError(
            "invalid-rdp-request", "el usuario RDP de la solicitud no es válido"
        )
    if (
        not isinstance(password, str)
        or not password
        or len(password) > 4096
        or any(character in password for character in ("\0", "\r", "\n"))
    ):
        raise ConfigCtlError(
            "invalid-rdp-request", "la contraseña RDP de la solicitud no es válida"
        )

    return {"username": username, "password": password}


def _command_path(name: str, environ: Mapping[str, str], which: Which) -> str | None:
    try:
        return which(name, path=environ.get("PATH"))
    except TypeError:
        return which(name)


def _windows_credential_state(
    environ: Mapping[str, str],
) -> tuple[bool, str, bool]:
    storage = Path(
        environ.get(
            "WINDOWSVM_STORAGE",
            str(_home(environ) / "containers" / "windows" / "storage"),
        )
    ).expanduser()
    credential_path = storage / ".windowsvm-credentials.json"
    descriptor = -1
    try:
        descriptor = os.open(
            credential_path,
            os.O_RDONLY | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0),
        )
        credential_status = os.fstat(descriptor)
        if (
            not stat.S_ISREG(credential_status.st_mode)
            or credential_status.st_uid != os.getuid()
            or stat.S_IMODE(credential_status.st_mode) != 0o600
            or credential_status.st_size > WINDOWS_CREDENTIAL_MAX_BYTES
        ):
            return False, "", False
        with os.fdopen(descriptor, "rb") as credential_file:
            descriptor = -1
            raw = credential_file.read(WINDOWS_CREDENTIAL_MAX_BYTES + 1)
        payload = json.loads(raw.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return False, "", False
    finally:
        if descriptor >= 0:
            os.close(descriptor)

    if not isinstance(payload, dict):
        return False, "", False
    schema_version = payload.get("schemaVersion")
    if schema_version == 1:
        if set(payload) != {"schemaVersion", "username", "password"}:
            return False, "", False
        policy_version = 0
    elif schema_version == 2:
        if set(payload) != {
            "schemaVersion",
            "username",
            "password",
            "rdpPolicyVersion",
        }:
            return False, "", False
        policy_version = payload.get("rdpPolicyVersion")
        if (
            isinstance(policy_version, bool)
            or not isinstance(policy_version, int)
            or policy_version < 0
        ):
            return False, "", False
    else:
        return False, "", False

    username = payload.get("username")
    password = payload.get("password")
    if (
        not isinstance(username, str)
        or not username
        or len(username) > 128
        or username != username.strip()
        or any(character in username for character in ("\0", "\r", "\n"))
        or not isinstance(password, str)
        or not password
        or len(password) > 4096
        or any(character in password for character in ("\0", "\r", "\n"))
    ):
        return False, "", False
    return True, username, policy_version >= 1


def _windows_installed(environ: Mapping[str, str]) -> bool:
    storage = Path(environ.get(
        "WINDOWSVM_STORAGE", str(_home(environ) / "containers/windows/storage")
    )).expanduser()
    return (storage / "data.img").is_file() and any(
        (storage / marker).is_file() for marker in ("windows.ver", "windows.mac")
    )


def _focus_windows_session(environ: Mapping[str, str], which: Which) -> bool:
    """Reuse this VM's desktop on Niri instead of opening a competing session."""
    niri = _command_path("niri", environ, which)
    if niri is None or not environ.get("NIRI_SOCKET"):
        return False
    try:
        response = subprocess.run(
            [niri, "msg", "--json", "windows"], capture_output=True, text=True,
            check=False, timeout=2, env=dict(environ),
        )
        if response.returncode != 0:
            return False
        windows = json.loads(response.stdout)
        if not isinstance(windows, list):
            return False
        for window in windows:
            if (isinstance(window, dict)
                    and window.get("app_id") in {"com.freerdp.client.sdl3", "xfreerdp"}
                    and window.get("title") == "FreeRDP: 127.0.0.1"
                    and type(window.get("id")) is int):
                focused = subprocess.run(
                    [niri, "msg", "action", "focus-window", "--id", str(window["id"])],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    check=False, timeout=2, env=dict(environ),
                )
                return focused.returncode == 0
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    return False


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
            timeout=2,
        )
        candidate = configured_host.stdout.strip().lower()
        if configured_host.returncode == 0 and GITLAB_HOST_RE.fullmatch(candidate):
            host = candidate
    except (OSError, subprocess.TimeoutExpired):
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
            timeout=2,
        )
    except (OSError, subprocess.TimeoutExpired):
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
    windows_available = _command_path("windowsvm", environ, which) is not None
    credential_stored, credential_username, rdp_resilience = (
        _windows_credential_state(environ)
    )
    windows_installed = _windows_installed(environ)

    return {
        "aws": {
            "activeProfile": active_aws_profile(environ, aws),
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
            "available": windows_available,
            "configured": windows_available and (credential_stored or windows_installed),
            "installed": windows_installed,
            "credentialStored": credential_stored,
            "credentialUsername": credential_username,
            "rdpResilience": rdp_resilience,
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
    active = active_aws_profile(environ, profiles)
    if active:
        stdout.write(f"Perfil AWS: {active}\n")
        return active
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
    if action in {"windows-up", "windows-rdp"} and _focus_windows_session(environ, which):
        # A pending textbox request must not survive a launch that reused a window.
        _consume_rdp_request(environ)
        stdout.write("Windows ya está abierto; se activó su ventana.\n")
        return {"action": action, "argv": argv, "command": "action",
                "exitCode": 0, "ok": True, "focusedExisting": True}
    child_environment: dict[str, str] | None = None
    if action in {
        "windows-up",
        "windows-rdp",
        "windows-unlock",
        "windows-password-reset",
        "windows-wipe",
    }:
        rdp_request = _consume_rdp_request(environ)
        if rdp_request is not None:
            child_environment = dict(environ)
            child_environment["WINDOWSVM_USER"] = rdp_request["username"]
            child_environment["WINDOWSVM_PASSWORD"] = rdp_request["password"]
            if action == "windows-wipe":
                child_environment["WINDOWSVM_WIPE_CONFIRM"] = "WIPE"

    try:
        runner_options: dict[str, Any] = {
            "check": False,
            "shell": False,
            "text": True,
        }
        if child_environment is not None:
            runner_options["env"] = child_environment
        completed = runner(argv, **runner_options)
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

    if action == "aws-login" and result["ok"]:
        remember_aws_profile(environ, profile)

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
