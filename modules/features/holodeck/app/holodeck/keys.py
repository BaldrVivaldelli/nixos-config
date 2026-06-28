from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

from .config import PUBLIC_KEYS_DIR
from .process import run
from .prompts import confirm
from .state import git_profile_file_for
from .ui import ui


def find_gpg_fingerprint(email: str) -> str:
    result = subprocess.run(
        ["gpg", "--list-secret-keys", "--with-colons", email],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return ""
    for line in result.stdout.splitlines():
        fields = line.split(":")
        if fields and fields[0] == "fpr" and len(fields) > 9:
            return fields[9]
    return ""


def is_gpg_fingerprint(value: str) -> bool:
    return bool(re.fullmatch(r"[A-Fa-f0-9]{40,}", value))


def ensure_gpg_key(name: str, email: str, mode: str = "prompt") -> str:
    fingerprint = find_gpg_fingerprint(email)
    if fingerprint:
        print(f"Using existing GPG key for {email}: {fingerprint}", file=sys.stderr)
        return fingerprint

    if mode == "prompt" and not confirm(f"Generate a new GPG signing key for {email}?"):
        return ""

    user_id = f"{name} <{email}>"
    print(f"Generating GPG key for {user_id}", file=sys.stderr)
    print("GPG may ask for a passphrase in a pinentry dialog.", file=sys.stderr)
    run(["gpg", "--quick-generate-key", user_id, "ed25519", "sign", "2y"])
    return find_gpg_fingerprint(email)


def write_git_profile(profile: str, name: str, email: str, fingerprint: str) -> None:
    lines = ["[user]\n", f"  name = {name}\n", f"  email = {email}\n"]
    if fingerprint:
        lines.append(f"  signingKey = {fingerprint}\n")
    lines.extend(["\n", "[init]\n", "  defaultBranch = main\n"])
    if fingerprint:
        lines.extend(
            [
                "\n",
                "[commit]\n",
                "  gpgSign = true\n",
                "\n",
                "[tag]\n",
                "  gpgSign = true\n",
                "\n",
                "[gpg]\n",
                "  program = gpg\n",
            ]
        )
    git_profile_file_for(profile).write_text("".join(lines))


def generate_ssh_key(ssh_key: Path, email: str, mode: str = "prompt") -> None:
    if ssh_key.exists():
        ui.ok(f"Using existing SSH key: {ssh_key}")
        return

    ui.info(f"Generating SSH key: {ssh_key}")
    args = ["ssh-keygen", "-t", "ed25519", "-C", email, "-f", str(ssh_key)]
    if mode == "auto":
        args.extend(["-N", ""])
    run(args)


def export_gpg_public_key(fingerprint: str, profile: str) -> Path | None:
    gpg_pub = PUBLIC_KEYS_DIR / f"{profile}-gpg.asc"
    with gpg_pub.open("w") as handle:
        result = subprocess.run(
            ["gpg", "--armor", "--export", fingerprint],
            stdout=handle,
            stderr=None,
            text=True,
            check=False,
        )
    if result.returncode == 0:
        return gpg_pub

    ui.error(f"Could not export GPG public key for {fingerprint}.")
    try:
        gpg_pub.unlink()
    except FileNotFoundError:
        pass
    return None

