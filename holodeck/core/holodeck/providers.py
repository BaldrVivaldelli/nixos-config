"""GitHub and GitLab provider integration."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from .errors import HolodeckError
from .platform import open_url
from .process import command_ok, command_output, run
from .ui import ui


def login_github(host: str) -> None:
    """Authenticate gh without letting it choose or upload an unrelated SSH key."""
    if command_ok(["gh", "auth", "status", "--hostname", host]):
        ui.ok(f"GitHub is already authenticated on {host}.")
    else:
        run(
            [
                "gh",
                "auth",
                "login",
                "--hostname",
                host,
                "--web",
                "--git-protocol",
                "ssh",
                "--skip-ssh-key",
                "--scopes",
                "write:public_key,read:public_key",
            ]
        )

    # Keep gh clone/repo operations on SSH as well. This does not upload keys.
    run(["gh", "config", "set", "git_protocol", "ssh", "--host", host])


def login_gitlab(host: str) -> None:
    if command_ok(["glab", "auth", "status", "--hostname", host]):
        ui.ok(f"GitLab is already authenticated on {host}.")
        return

    web_login = run(["glab", "auth", "login", "--hostname", host, "--web"], check=False)
    if web_login.returncode == 0:
        return

    ui.warn("GitLab web login was not available; falling back to glab interactive login.")
    run(["glab", "auth", "login", "--hostname", host])


def login_provider(provider: str, host: str) -> None:
    if provider == "github":
        login_github(host)
        return
    if provider == "gitlab":
        login_gitlab(host)
        return
    raise HolodeckError(f"Unknown provider: {provider}")


def _public_key_identity(path: Path) -> str:
    """Return '<algorithm> <payload>' so comments do not affect comparisons."""
    try:
        parts = path.read_text().strip().split()
    except OSError as exc:
        raise HolodeckError(f"Could not read SSH public key {path}: {exc}") from exc
    if len(parts) < 2:
        raise HolodeckError(f"Invalid SSH public key: {path}")
    return " ".join(parts[:2])


def _github_key_exists(host: str, ssh_pub: Path) -> bool:
    result = subprocess.run(
        [
            "gh",
            "api",
            "--hostname",
            host,
            "--paginate",
            "user/keys",
            "--jq",
            ".[].key",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return False
    expected = _public_key_identity(ssh_pub)
    return any(line.strip() == expected for line in result.stdout.splitlines())


def upload_github_ssh_key(host: str, title: str, ssh_pub: Path) -> None:
    """Upload the exact key Holodeck configures, or fail loudly."""
    if not ssh_pub.exists():
        raise HolodeckError(f"SSH public key does not exist: {ssh_pub}")

    if _github_key_exists(host, ssh_pub):
        ui.ok("Holodeck SSH key is already registered in GitHub.")
        return

    def add_key() -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["gh", "ssh-key", "add", str(ssh_pub), "--title", title],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )

    result = add_key()
    combined = "\n".join(part for part in (result.stdout, result.stderr) if part).strip()
    lowered = combined.lower()

    # A key can already belong to the account while the token lacks read scope.
    if result.returncode != 0 and (
        "key is already in use" in lowered
        or "already exists" in lowered
        or "unprocessable entity" in lowered
    ):
        ui.ok("Holodeck SSH key is already registered in GitHub.")
        return

    if result.returncode != 0:
        ui.info("Refreshing GitHub permission to register the Holodeck SSH key.")
        refreshed = run(
            [
                "gh",
                "auth",
                "refresh",
                "--hostname",
                host,
                "--scopes",
                "write:public_key,read:public_key",
            ],
            check=False,
        )
        if refreshed.returncode == 0:
            result = add_key()
            combined = "\n".join(
                part for part in (result.stdout, result.stderr) if part
            ).strip()

    if result.returncode != 0:
        detail = combined or "gh ssh-key add failed without details"
        raise HolodeckError(
            "GitHub authentication succeeded, but the Holodeck SSH key could not "
            f"be registered. Git was not reconfigured. Details: {detail}"
        )

    ui.ok("Holodeck SSH key uploaded to GitHub.")


def upload_github_gpg_key(host: str, gpg_pub: Path) -> None:
    result = subprocess.run(
        ["gh", "gpg-key", "add", str(gpg_pub)],
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode == 0:
        return
    error = result.stderr or ""
    if "insufficient oauth scopes" in error.lower():
        ui.warn("GitHub requires the write:gpg_key scope before Holodeck can upload your GPG key.")
        ui.info("Opening GitHub auth refresh for that scope...")
        refreshed = run(
            ["gh", "auth", "refresh", "--hostname", host, "--scopes", "write:gpg_key"],
            check=False,
        )
        if refreshed.returncode == 0:
            run(["gh", "gpg-key", "add", str(gpg_pub)], check=False)
            return
        ui.warn("GitHub did not grant the extra scope automatically.")
        print("Run this when you want to upload the GPG key:")
        print(f"  gh auth refresh --hostname {host} --scopes write:gpg_key")
        print(f"  gh gpg-key add {gpg_pub}")
        return

    if error:
        print(error, end="" if error.endswith("\n") else "\n", file=sys.stderr)


def upload_keys(
    provider: str,
    host: str,
    title: str,
    ssh_pub: Path,
    gpg_pub: Path | None,
) -> None:
    if provider == "github":
        upload_github_ssh_key(host, title, ssh_pub)
        if gpg_pub and gpg_pub.exists():
            upload_github_gpg_key(host, gpg_pub)
        return
    if provider == "gitlab":
        if ssh_pub.exists():
            result = run(
                ["glab", "ssh-key", "add", str(ssh_pub), "--title", title],
                check=False,
            )
            if result.returncode != 0:
                raise HolodeckError("GitLab authentication succeeded, but the SSH key upload failed.")
        if gpg_pub and gpg_pub.exists():
            if command_ok(["glab", "gpg-key", "add", "--help"]):
                run(["glab", "gpg-key", "add", str(gpg_pub)], check=False)
            else:
                settings_url = f"https://{host}/-/user_settings/gpg_keys"
                ui.warn("glab does not expose gpg-key add here. Opening GitLab GPG settings.")
                if not open_url(settings_url):
                    print(f"GitLab GPG settings: {settings_url}")
                print(f"Public GPG key: {gpg_pub}")


def github_api_field(host: str, field: str) -> str:
    return command_output(["gh", "api", "--hostname", host, "user", "--jq", f".{field} // \"\""])


def github_primary_email(host: str) -> str:
    return command_output(
        [
            "gh",
            "api",
            "--hostname",
            host,
            "user/emails",
            "--jq",
            'map(select(.primary == true and .verified == true))[0].email // ""',
        ]
    )


def github_noreply_email(login: str, account_id: str) -> str:
    if account_id:
        return f"{account_id}+{login}@users.noreply.github.com"
    return f"{login}@users.noreply.github.com"
