"""Portable identity and provider workflows."""

from __future__ import annotations

import glob
import os
import shutil
import socket
import subprocess
import tempfile
from pathlib import Path

from .config import (
    DEFAULT_GITHUB_HOST,
    DEFAULT_GITLAB_HOST,
    DEFAULT_PERSONAL_DIR,
    DEFAULT_WORK_DIR,
    GIT_BEGIN,
    GIT_END,
    GITCONFIG_FILE,
    HOME,
    HOLODECK_DIR,
    SSH_BEGIN,
    SSH_CONFIG_FILE,
    SSH_END,
)
from .errors import HolodeckError
from .keys import (
    ensure_gpg_key,
    export_gpg_public_key,
    generate_ssh_key,
    is_gpg_fingerprint,
    write_git_profile,
)
from .process import run, run_quiet
from .prompts import confirm, prompt
from .providers import (
    github_api_field,
    github_noreply_email,
    github_primary_email,
    login_github,
    login_provider,
    upload_keys,
)
from .state import (
    ensure_dirs,
    env_line,
    expand_path,
    git_global_value,
    git_profile_file_for,
    profile_file_for,
    profiles,
    rebuild_gitconfig_block,
    rebuild_ssh_config_block,
    remove_managed_block,
    sanitize_id,
    ssh_key_file_for,
)
from .ui import ui


def require_user_context() -> None:
    get_effective_user_id = getattr(os, "geteuid", None)
    if get_effective_user_id is not None and get_effective_user_id() == 0:
        raise HolodeckError(
            "Este comando maneja identidad y credenciales personales. "
            "Ejecutalo como tu usuario normal, sin sudo."
        )


def write_profile_env(
    profile: str,
    provider: str,
    host: str,
    projects_dir_abs: str,
    name: str,
    email: str,
    ssh_key: Path,
    fingerprint: str,
    ssh_hostname: str = "",
    ssh_port: str = "",
) -> None:
    profile_file_for(profile).write_text(
        "".join(
            [
                env_line("HOLODECK_PROFILE", profile),
                env_line("HOLODECK_PROVIDER", provider),
                env_line("HOLODECK_HOST", host),
                env_line("HOLODECK_PROJECTS_DIR", projects_dir_abs),
                env_line("HOLODECK_NAME", name),
                env_line("HOLODECK_EMAIL", email),
                env_line("HOLODECK_SSH_KEY", str(ssh_key)),
                env_line("HOLODECK_SSH_HOSTNAME", ssh_hostname),
                env_line("HOLODECK_SSH_PORT", ssh_port),
                env_line("HOLODECK_GPG_FINGERPRINT", fingerprint),
            ]
        )
    )


def _ssh_test(
    host: str,
    ssh_key: Path,
    *,
    hostname: str | None = None,
    port: int | None = None,
) -> tuple[bool, str]:
    destination = hostname or host
    args = [
        "ssh",
        "-T",
        "-F",
        "/dev/null",
        "-i",
        str(ssh_key),
        "-o",
        "IdentitiesOnly=yes",
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=accept-new",
        "-o",
        "ConnectTimeout=10",
    ]
    if port is not None:
        args.extend(["-p", str(port)])
    args.append(f"git@{destination}")
    result = subprocess.run(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    output = "\n".join(part for part in (result.stdout, result.stderr) if part).strip()
    lowered = output.lower()
    success = result.returncode == 0 or any(
        marker in lowered
        for marker in (
            "successfully authenticated",
            "welcome to gitlab",
            "authenticated via ssh key",
        )
    )
    return success, output


def _resolve_ssh_endpoint(provider: str, host: str, ssh_key: Path) -> tuple[str, str]:
    ui.info(f"Testing the exact Holodeck SSH key against {host}...")
    success, detail = _ssh_test(host, ssh_key)
    if success:
        ui.ok(f"SSH authentication works on {host}:22.")
        return "", ""

    # GitHub.com officially supports SSH over HTTPS port 443. This also fixes
    # networks that block outbound port 22.
    if provider == "github" and host == "github.com":
        ui.warn("SSH on port 22 did not work; trying GitHub SSH over port 443.")
        fallback_host = "ssh.github.com"
        success_443, detail_443 = _ssh_test(
            host,
            ssh_key,
            hostname=fallback_host,
            port=443,
        )
        if success_443:
            ui.ok("SSH authentication works through ssh.github.com:443.")
            return fallback_host, "443"
        detail = "\n".join(part for part in (detail, detail_443) if part)

    message = detail or "SSH returned no diagnostic output."
    raise HolodeckError(
        "GitHub CLI is authenticated, but Git over SSH is not working with "
        f"the Holodeck key {ssh_key}. No broken Git configuration was activated. "
        f"Details: {message}"
    )


def _verify_git_profile(profile: str, projects_dir_abs: str, expected_email: str) -> None:
    """Prove that includeIf activates inside the configured project tree."""
    projects_dir = Path(projects_dir_abs)
    projects_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".holodeck-check-", dir=projects_dir) as temp_dir:
        run(["git", "-C", temp_dir, "init", "--quiet"])
        result = subprocess.run(
            ["git", "-C", temp_dir, "config", "--includes", "--get", "user.email"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
    actual = result.stdout.strip()
    if result.returncode != 0 or actual != expected_email:
        raise HolodeckError(
            "Holodeck wrote the profile but Git did not load it through includeIf. "
            f"Expected {expected_email!r}, got {actual!r}. Profile: "
            f"{git_profile_file_for(profile)}"
        )
    ui.ok("Git profile routing works inside the configured projects directory.")


def write_local_profile(
    provider: str,
    profile: str,
    host: str,
    projects_dir_abs: str,
    name: str,
    email: str,
    auth_ok: bool,
    ssh_mode: str = "prompt",
    gpg_mode: str = "prompt",
    upload_mode: str = "prompt",
) -> None:
    ensure_dirs()
    Path(projects_dir_abs).mkdir(parents=True, exist_ok=True)

    if not profile:
        raise HolodeckError("Invalid profile name.")
    if not name or not email:
        raise HolodeckError("Name and email are required.")

    ssh_key = ssh_key_file_for(profile, provider)
    generate_ssh_key(ssh_key, email, ssh_mode)
    ssh_key.chmod(0o600)
    ssh_pub = Path(f"{ssh_key}.pub")

    # GPG is optional and must never block the Git/SSH setup.
    fingerprint = ensure_gpg_key(name, email, gpg_mode)
    gpg_pub: Path | None = None
    if fingerprint and is_gpg_fingerprint(fingerprint):
        gpg_pub = export_gpg_public_key(fingerprint, profile)
    elif fingerprint:
        ui.warn(f"Ignoring invalid GPG fingerprint: {fingerprint}")
        fingerprint = ""

    title = f"holodeck-{profile}@{socket.gethostname()}"
    should_upload = auth_ok and (
        upload_mode == "auto" or confirm(f"Upload SSH/GPG public keys to {provider}?")
    )
    if should_upload:
        upload_keys(provider, host, title, ssh_pub, gpg_pub)

    ssh_hostname = ""
    ssh_port = ""
    if auth_ok and provider in {"github", "gitlab"}:
        ssh_hostname, ssh_port = _resolve_ssh_endpoint(provider, host, ssh_key)

    # Activate local configuration only after key upload and SSH verification.
    write_git_profile(profile, provider, host, name, email, ssh_key, fingerprint)
    write_profile_env(
        profile,
        provider,
        host,
        projects_dir_abs,
        name,
        email,
        ssh_key,
        fingerprint,
        ssh_hostname,
        ssh_port,
    )
    rebuild_gitconfig_block()
    rebuild_ssh_config_block()
    _verify_git_profile(profile, projects_dir_abs, email)

    print()
    ui.ok(f"Profile configured and verified: {profile}")
    print(f"Projects: {projects_dir_abs}")
    print(f"Git config: {git_profile_file_for(profile)}")
    print(f"SSH key: {ssh_key}")


def configure_profile(provider: str, default_profile: str, default_host: str, default_dir: str) -> None:
    profile = sanitize_id(prompt("Profile name", default_profile))
    if not profile:
        raise HolodeckError("Invalid profile name.")
    host = prompt("Host", default_host)
    projects_dir_abs = expand_path(prompt("Projects directory for this profile", default_dir))
    name = prompt("Git commit name", git_global_value("user.name"))
    email = prompt("Git commit email", git_global_value("user.email"))
    auth_ok = False
    if confirm(f"Authenticate {provider} on {host} now?"):
        try:
            login_provider(provider, host)
            auth_ok = True
        except subprocess.CalledProcessError:
            ui.warn("Authentication failed or was cancelled. Continuing with local config only.")

    write_local_profile(provider, profile, host, projects_dir_abs, name, email, auth_ok)


def configure_github_profile() -> None:
    host = DEFAULT_GITHUB_HOST
    login_github(host)
    login = github_api_field(host, "login")
    account_id = github_api_field(host, "id")
    name = github_api_field(host, "name")
    email = github_api_field(host, "email")

    if not login:
        raise HolodeckError("Could not read the GitHub account from gh.")
    if not name:
        name = login
    if not email:
        email = github_primary_email(host)
    if not email:
        email = github_noreply_email(login, account_id)
    profile = sanitize_id(login)
    projects_dir_abs = expand_path(DEFAULT_PERSONAL_DIR)
    print(f"{ui.label('Using GitHub account')}: {login}")
    print(f"{ui.label('Git commit name')}: {name}")
    print(f"{ui.label('Git commit email')}: {email}")
    print(f"{ui.label('Projects directory')}: {projects_dir_abs}")
    write_local_profile(
        "github",
        profile,
        host,
        projects_dir_abs,
        name,
        email,
        True,
        "auto",
        "off",
        "auto",
    )


def setup() -> None:
    require_user_context()
    ui.heading("Holodeck setup")
    print()
    if confirm("Configure GitHub personal profile?"):
        configure_github_profile()

    print()
    if confirm("Configure GitLab work profile?"):
        configure_profile("gitlab", "work", DEFAULT_GITLAB_HOST, DEFAULT_WORK_DIR)


def auth_command(provider: str) -> None:
    require_user_context()
    if provider == "github":
        host = prompt("GitHub host", DEFAULT_GITHUB_HOST)
    elif provider == "gitlab":
        host = prompt("GitLab host", DEFAULT_GITLAB_HOST)
    else:
        raise HolodeckError("Usage: holodeck login <github|gitlab>")
    login_provider(provider, host)


def profile_command(provider: str) -> None:
    require_user_context()
    if provider == "github":
        configure_github_profile()
    elif provider == "gitlab":
        configure_profile("gitlab", "work", DEFAULT_GITLAB_HOST, DEFAULT_WORK_DIR)
    else:
        raise HolodeckError("Usage: holodeck profile <github|gitlab>")


def _doctor_profile(profile: dict[str, str]) -> None:
    name = profile.get("HOLODECK_PROFILE", "")
    provider = profile.get("HOLODECK_PROVIDER", "")
    host = profile.get("HOLODECK_HOST", "")
    projects_dir = profile.get("HOLODECK_PROJECTS_DIR", "")
    email = profile.get("HOLODECK_EMAIL", "")
    ssh_key_value = profile.get("HOLODECK_SSH_KEY", "")
    ssh_hostname = profile.get("HOLODECK_SSH_HOSTNAME", "") or None
    ssh_port_value = profile.get("HOLODECK_SSH_PORT", "")
    ssh_port = int(ssh_port_value) if ssh_port_value.isdigit() else None

    ui.heading(f"Profile: {name}")
    print(f"  Provider: {provider}")
    print(f"  Host: {host}")
    print(f"  Projects: {projects_dir}")
    print(f"  Email: {email}")
    print(f"  SSH key: {ssh_key_value}")
    print(f"  GPG: {profile.get('HOLODECK_GPG_FINGERPRINT') or 'disabled'}")

    ssh_key = Path(ssh_key_value)
    if not ssh_key.exists() or not Path(f"{ssh_key}.pub").exists():
        ui.error("SSH key pair is incomplete.")
    else:
        success, detail = _ssh_test(
            host,
            ssh_key,
            hostname=ssh_hostname,
            port=ssh_port,
        )
        if success:
            ui.ok("SSH authentication: working")
        else:
            ui.error(f"SSH authentication: failed ({detail or 'no details'})")

    try:
        _verify_git_profile(name, projects_dir, email)
    except HolodeckError as exc:
        ui.error(str(exc))
    print()


def doctor() -> None:
    print(f"{ui.label('Holodeck directory')}: {HOLODECK_DIR}")
    print()
    loaded_profiles = profiles()
    if not loaded_profiles:
        ui.warn("No Holodeck profiles configured. Run: holodeck github")
    else:
        for profile in loaded_profiles:
            _doctor_profile(profile)

    ui.heading("GitHub auth:")
    run(["gh", "auth", "status", "--hostname", DEFAULT_GITHUB_HOST], check=False)
    print()
    ui.heading("GitLab auth:")
    run(["glab", "auth", "status", "--hostname", DEFAULT_GITLAB_HOST], check=False)


def logout_known_hosts() -> None:
    for profile in profiles():
        host = profile.get("HOLODECK_HOST", "")
        provider = profile.get("HOLODECK_PROVIDER", "")
        if not host:
            continue
        if provider == "github":
            run_quiet(["gh", "auth", "logout", "--hostname", host, "--yes"])
        elif provider == "gitlab":
            run_quiet(["glab", "auth", "logout", "--hostname", host], input_text="y\n")


def delete_tracked_gpg_keys() -> None:
    for profile in profiles():
        fingerprint = profile.get("HOLODECK_GPG_FINGERPRINT", "")
        if fingerprint:
            ui.warn(f"Deleting Holodeck-tracked GPG key: {fingerprint}")
            run_quiet(["gpg", "--batch", "--yes", "--delete-secret-and-public-key", fingerprint])


def purge() -> None:
    require_user_context()
    print("This removes local state managed by Holodeck:")
    print("  - managed blocks in ~/.gitconfig and ~/.ssh/config")
    print("  - ~/.config/holodeck")
    print("  - ~/.ssh/holodeck_* keys")
    print("  - Holodeck-tracked local GPG keys")
    print("  - gh/glab local auth for Holodeck profile hosts")
    print()
    print("It does not rewrite git history and does not remove uploaded public keys from GitHub/GitLab.")
    print()
    purge_prompt = ui.label("Type 'purge holodeck' to continue")
    if input(f"{purge_prompt}: ") != "purge holodeck":
        ui.warn("Cancelled.")
        raise SystemExit(1)
    logout_known_hosts()
    delete_tracked_gpg_keys()
    remove_managed_block(GITCONFIG_FILE, GIT_BEGIN, GIT_END)
    remove_managed_block(SSH_CONFIG_FILE, SSH_BEGIN, SSH_END)
    for key_path in glob.glob(str(HOME / ".ssh" / "holodeck_*")):
        try:
            Path(key_path).unlink()
        except FileNotFoundError:
            pass
    shutil.rmtree(HOLODECK_DIR, ignore_errors=True)
    ui.ok("Holodeck local state removed.")
