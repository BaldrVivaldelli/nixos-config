from __future__ import annotations

import re
import shlex
import shutil
from pathlib import Path

from .config import (
    GIT_BEGIN,
    GIT_END,
    GIT_PROFILES_DIR,
    GITCONFIG_FILE,
    HOME,
    HOLODECK_DIR,
    PROFILES_DIR,
    PUBLIC_KEYS_DIR,
    SSH_BEGIN,
    SSH_CONFIG_FILE,
    SSH_END,
)
from .process import command_output


def ensure_dirs() -> None:
    PROFILES_DIR.mkdir(parents=True, exist_ok=True)
    GIT_PROFILES_DIR.mkdir(parents=True, exist_ok=True)
    PUBLIC_KEYS_DIR.mkdir(parents=True, exist_ok=True)
    ssh_dir = HOME / ".ssh"
    ssh_dir.mkdir(parents=True, exist_ok=True)
    ssh_dir.chmod(0o700)


def expand_path(value: str) -> str:
    if value in {"~", "$HOME"}:
        return str(HOME)
    if value.startswith("~/"):
        return str(HOME / value[2:])
    if value.startswith("$HOME/"):
        return str(HOME / value[6:])
    return value


def sanitize_id(value: str) -> str:
    cleaned = re.sub(r"[^a-z0-9_-]", "-", value.lower())
    return cleaned.strip("-")


def env_line(key: str, value: str) -> str:
    return f"{key}={shlex.quote(value)}\n"


def profile_file_for(profile: str) -> Path:
    return PROFILES_DIR / f"{profile}.env"


def git_profile_file_for(profile: str) -> Path:
    return GIT_PROFILES_DIR / f"{profile}.gitconfig"


def ssh_key_file_for(profile: str, provider: str) -> Path:
    return HOME / ".ssh" / f"holodeck_{profile}_{provider}"


def remove_managed_block(path: Path, begin: str, end: str) -> None:
    if not path.exists():
        return

    output: list[str] = []
    skip = False
    for line in path.read_text().splitlines(keepends=True):
        value = line.rstrip("\n")
        if value == begin:
            skip = True
            continue
        if value == end:
            skip = False
            continue
        if not skip:
            output.append(line)

    shutil.copy2(path, f"{path}.holodeck.bak")
    path.write_text("".join(output))


def profile_files() -> list[Path]:
    if not PROFILES_DIR.is_dir():
        return []
    return sorted(PROFILES_DIR.glob("*.env"))


def parse_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :]
        if "=" not in line:
            continue
        key, raw_value = line.split("=", 1)
        try:
            parts = shlex.split(raw_value)
            value = parts[0] if parts else ""
        except ValueError:
            value = raw_value.strip("\"'")
        values[key] = value
    return values


def profiles() -> list[dict[str, str]]:
    return [parse_env_file(path) for path in profile_files()]


def append_block(path: Path, text: str) -> None:
    path.touch(exist_ok=True)
    needs_newline = path.stat().st_size > 0 and not path.read_bytes().endswith(b"\n")
    with path.open("a") as handle:
        if needs_newline:
            handle.write("\n")
        handle.write(text)


def rebuild_gitconfig_block() -> None:
    ensure_dirs()
    remove_managed_block(GITCONFIG_FILE, GIT_BEGIN, GIT_END)

    lines = [f"{GIT_BEGIN}\n"]
    has_include = False
    for profile in profiles():
        name = profile.get("HOLODECK_PROFILE", "")
        projects_dir = profile.get("HOLODECK_PROJECTS_DIR", "")
        path = git_profile_file_for(name)
        if projects_dir and path.exists():
            has_include = True
            lines.append(f'[includeIf "gitdir:{projects_dir}/**"]\n')
            lines.append(f"  path = {path}\n\n")
    lines.append(f"{GIT_END}\n")

    if has_include:
        append_block(GITCONFIG_FILE, "".join(lines))


def rebuild_ssh_config_block() -> None:
    ensure_dirs()
    remove_managed_block(SSH_CONFIG_FILE, SSH_BEGIN, SSH_END)

    lines = [f"{SSH_BEGIN}\n"]
    has_host = False
    for profile in profiles():
        host = profile.get("HOLODECK_HOST", "")
        ssh_key = profile.get("HOLODECK_SSH_KEY", "")
        if host and ssh_key:
            has_host = True
            lines.append(f"Host {host}\n")
            lines.append(f"  HostName {host}\n")
            lines.append("  User git\n")
            lines.append(f"  IdentityFile {ssh_key}\n")
            lines.append("  IdentitiesOnly yes\n\n")
    lines.append(f"{SSH_END}\n")

    if has_host:
        append_block(SSH_CONFIG_FILE, "".join(lines))
        SSH_CONFIG_FILE.chmod(0o600)


def git_global_value(key: str) -> str:
    return command_output(["git", "config", "--global", key])


def holodeck_dir() -> Path:
    return HOLODECK_DIR

