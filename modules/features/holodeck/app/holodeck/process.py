from __future__ import annotations

import shlex
import subprocess


def run(args: list[str], *, check: bool = True, **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(args, check=check, **kwargs)


def command_ok(args: list[str]) -> bool:
    return (
        subprocess.run(
            args,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode
        == 0
    )


def command_output(args: list[str]) -> str:
    result = subprocess.run(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def run_quiet(
    args: list[str],
    *,
    input_text: str | None = None,
) -> subprocess.CompletedProcess:
    return subprocess.run(
        args,
        input=input_text,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )


def format_cmd(cmd: object) -> str:
    if isinstance(cmd, list):
        return shlex.join(str(part) for part in cmd)
    return str(cmd)

