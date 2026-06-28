from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from .errors import HolodeckError
from .process import command_ok, command_output, run, run_quiet
from .ui import ui


def login_github(host: str) -> None:
    if command_ok(["gh", "auth", "status", "--hostname", host]):
        ui.ok(f"GitHub is already authenticated on {host}.")
        return
    run(["gh", "auth", "login", "--hostname", host, "--web", "--git-protocol", "ssh"])


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
        if ssh_pub.exists():
            run(["gh", "ssh-key", "add", str(ssh_pub), "--title", title], check=False)
        if gpg_pub and gpg_pub.exists():
            upload_github_gpg_key(host, gpg_pub)
        return

    if provider == "gitlab":
        if ssh_pub.exists():
            run(["glab", "ssh-key", "add", str(ssh_pub), "--title", title], check=False)
        if gpg_pub and gpg_pub.exists():
            if command_ok(["glab", "gpg-key", "add", "--help"]):
                run(["glab", "gpg-key", "add", str(gpg_pub)], check=False)
            else:
                ui.warn("glab does not expose gpg-key add here. Opening GitLab GPG settings.")
                run_quiet(["xdg-open", f"https://{host}/-/user_settings/gpg_keys"])
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
