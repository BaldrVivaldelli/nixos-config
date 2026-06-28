from __future__ import annotations

import glob
import shutil
import socket
import subprocess
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


def write_profile_env(
    profile: str,
    provider: str,
    host: str,
    projects_dir_abs: str,
    name: str,
    email: str,
    ssh_key: Path,
    fingerprint: str,
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
                env_line("HOLODECK_GPG_FINGERPRINT", fingerprint),
            ]
        )
    )


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

    fingerprint = ensure_gpg_key(name, email, gpg_mode)
    gpg_pub: Path | None = None
    if fingerprint and is_gpg_fingerprint(fingerprint):
        gpg_pub = export_gpg_public_key(fingerprint, profile)
    elif fingerprint:
        ui.warn(f"Ignoring invalid GPG fingerprint: {fingerprint}")
        fingerprint = ""

    write_git_profile(profile, name, email, fingerprint)
    write_profile_env(profile, provider, host, projects_dir_abs, name, email, ssh_key, fingerprint)
    rebuild_gitconfig_block()
    rebuild_ssh_config_block()

    title = f"holodeck-{profile}@{socket.gethostname()}"
    should_upload = auth_ok and (
        upload_mode == "auto" or confirm(f"Upload SSH/GPG public keys to {provider}?")
    )
    if should_upload:
        upload_keys(provider, host, title, ssh_pub, gpg_pub)

    print()
    ui.ok(f"Profile configured: {profile}")
    print(f"Projects: {projects_dir_abs}")
    print(f"Git config: {git_profile_file_for(profile)}")


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
        "auto",
        "auto",
    )


def setup() -> None:
    ui.heading("Holodeck setup")
    print()
    if confirm("Configure GitHub personal profile?"):
        configure_github_profile()

    print()
    if confirm("Configure GitLab work profile?"):
        configure_profile("gitlab", "work", DEFAULT_GITLAB_HOST, DEFAULT_WORK_DIR)


def auth_command(provider: str) -> None:
    if provider == "github":
        host = prompt("GitHub host", DEFAULT_GITHUB_HOST)
    elif provider == "gitlab":
        host = prompt("GitLab host", DEFAULT_GITLAB_HOST)
    else:
        raise HolodeckError("Usage: holodeck login <github|gitlab>")
    login_provider(provider, host)


def profile_command(provider: str) -> None:
    if provider == "github":
        configure_github_profile()
    elif provider == "gitlab":
        configure_profile("gitlab", "work", DEFAULT_GITLAB_HOST, DEFAULT_WORK_DIR)
    else:
        raise HolodeckError("Usage: holodeck profile <github|gitlab>")


def doctor() -> None:
    print(f"{ui.label('Holodeck directory')}: {HOLODECK_DIR}")
    print()

    loaded_profiles = profiles()
    if not loaded_profiles:
        ui.warn("No Holodeck profiles configured.")
    else:
        for profile in loaded_profiles:
            ui.heading(f"Profile: {profile.get('HOLODECK_PROFILE', '')}")
            print(f"  Provider: {profile.get('HOLODECK_PROVIDER', '')}")
            print(f"  Host: {profile.get('HOLODECK_HOST', '')}")
            print(f"  Projects: {profile.get('HOLODECK_PROJECTS_DIR', '')}")
            print(f"  Email: {profile.get('HOLODECK_EMAIL', '')}")
            print(f"  SSH key: {profile.get('HOLODECK_SSH_KEY', '')}")
            print(f"  GPG: {profile.get('HOLODECK_GPG_FINGERPRINT') or 'none'}")
            print()

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

