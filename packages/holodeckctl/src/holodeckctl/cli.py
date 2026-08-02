from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys
from collections.abc import Callable, Sequence
from pathlib import Path
from typing import Any, TextIO

from .errors import ConfigCtlError
from .integrations import ALL_ACTIONS, execute_action, integration_status
from .model import ALL_SETTABLE_KEYS, SETTERS, default_ir, digest_ir, set_value
from .storage import atomic_write_ir, exclusive_lock, load_ir

DEFAULT_IR_NAME = "holodeck.local.json"
ENV_REPO = "HOLODECK_REPO"
ENV_IR = "HOLODECK_IR"
ENV_LOCK_TIMEOUT = "HOLODECK_LOCK_TIMEOUT"

Runner = Callable[..., subprocess.CompletedProcess[str]]


class Parser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise ConfigCtlError("usage", message)


def _add_common_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--repo",
        metavar="PATH",
        help=f"ruta del repo (env: {ENV_REPO}; default: repo desde cwd)",
    )
    parser.add_argument(
        "--ir",
        metavar="PATH",
        help=f"ruta del IR (env: {ENV_IR}; default: <repo>/{DEFAULT_IR_NAME})",
    )
    parser.add_argument(
        "--lock-timeout",
        metavar="SECONDS",
        type=float,
        help=f"espera del lock (env: {ENV_LOCK_TIMEOUT}; default: 10)",
    )
    parser.add_argument("--json", action="store_true", help="salida JSON estable")


def make_parser() -> Parser:
    parser = Parser(
        prog="holodeckctl",
        description="Administra el IR declarativo local de Holodeck usado por Noctalia y Nix.",
    )
    _add_common_options(parser)
    subparsers = parser.add_subparsers(dest="command", metavar="COMMAND")

    help_parser = subparsers.add_parser("help", help="muestra ayuda general o de un comando")
    help_parser.add_argument(
        "topic",
        nargs="?",
        choices=("status", "init", "set", "plan", "apply", "action"),
    )

    subparsers.add_parser("status", help="muestra el IR efectivo y su validez")

    init_parser = subparsers.add_parser("init", help="crea el IR con defaults seguros")
    init_parser.add_argument("--force", action="store_true", help="reemplaza un IR existente")

    set_parser = subparsers.add_parser("set", help="modifica una clave permitida del IR")
    set_parser.add_argument("key", choices=ALL_SETTABLE_KEYS)
    set_parser.add_argument("value")

    subparsers.add_parser("plan", help="muestra exactamente qué argv ejecutaría apply")
    subparsers.add_parser("apply", help="aplica el IR mediante install.sh")

    action_parser = subparsers.add_parser(
        "action", help="abre una integración permitida en la terminal actual"
    )
    action_parser.add_argument("name", choices=ALL_ACTIONS)
    return parser


def _discover_repo(start: Path) -> Path:
    resolved = start.expanduser().resolve()
    candidates = (resolved, *resolved.parents) if resolved.is_dir() else resolved.parents
    for candidate in candidates:
        if (candidate / "flake.nix").is_file() and (candidate / "install.sh").is_file():
            return candidate
    return resolved


def _resolve_context(args: argparse.Namespace, environ: dict[str, str]) -> tuple[Path, Path, float]:
    repo_value = args.repo or environ.get(ENV_REPO)
    repo = (
        Path(repo_value).expanduser().resolve()
        if repo_value
        else _discover_repo(Path.cwd())
    )
    ir_value = args.ir or environ.get(ENV_IR)
    if ir_value:
        raw_ir = Path(ir_value).expanduser()
        ir_path = (raw_ir if raw_ir.is_absolute() else repo / raw_ir).resolve()
    else:
        ir_path = repo / DEFAULT_IR_NAME

    timeout_value: float | str = args.lock_timeout
    if timeout_value is None:
        timeout_value = environ.get(ENV_LOCK_TIMEOUT, "10")
    try:
        timeout = float(timeout_value)
    except (TypeError, ValueError) as exc:
        raise ConfigCtlError("invalid-timeout", "lock-timeout debe ser un número") from exc
    if not math.isfinite(timeout) or timeout < 0 or timeout > 300:
        raise ConfigCtlError(
            "invalid-timeout", "lock-timeout debe estar entre 0 y 300 segundos"
        )
    return repo, ir_path, timeout


def _emit_json(stream: TextIO, payload: dict[str, Any]) -> None:
    stream.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True))
    stream.write("\n")


def _emit_result(stream: TextIO, json_output: bool, payload: dict[str, Any], text: str) -> None:
    if json_output:
        _emit_json(stream, payload)
    else:
        stream.write(text.rstrip("\n") + "\n")


def _status(
    repo: Path, ir_path: Path, environ: dict[str, str]
) -> dict[str, Any]:
    exists = ir_path.exists()
    source = "file" if exists else "defaults"
    ir = load_ir(ir_path) if exists else default_ir()
    return {
        "command": "status",
        "exists": exists,
        "ir": ir,
        "irPath": str(ir_path),
        "integrations": integration_status(environ),
        "ok": True,
        "repoPath": str(repo),
        "source": source,
        "valid": True,
    }


def _init(ir_path: Path, timeout: float, force: bool) -> dict[str, Any]:
    with exclusive_lock(ir_path, timeout):
        exists = ir_path.exists()
        if exists and not force:
            ir = load_ir(ir_path)
            changed = False
        else:
            ir = default_ir()
            atomic_write_ir(ir_path, ir)
            changed = True
    return {
        "changed": changed,
        "command": "init",
        "ir": ir,
        "irPath": str(ir_path),
        "ok": True,
    }


def _set(ir_path: Path, timeout: float, key: str, value: str) -> dict[str, Any]:
    with exclusive_lock(ir_path, timeout):
        current = load_ir(ir_path) if ir_path.exists() else default_ir()
        updated = set_value(current, key, value)
        changed = updated != current or not ir_path.exists()
        if changed:
            atomic_write_ir(ir_path, updated)
    return {
        "changed": changed,
        "command": "set",
        "ir": updated,
        "irPath": str(ir_path),
        "key": key,
        "ok": True,
        "value": value.strip() if key == "appearance.theme.builtin" else value,
    }


def _make_plan(repo: Path, ir: dict[str, Any]) -> dict[str, Any]:
    install_script = repo / "install.sh"
    if not repo.is_dir():
        raise ConfigCtlError("invalid-repo", f"no existe el directorio del repo: {repo}")
    if not install_script.is_file():
        raise ConfigCtlError("invalid-repo", f"no existe {install_script}")

    target = ir["deployment"]["target"]
    return {
        "argv": ["bash", str(install_script), target],
        "irDigest": digest_ir(ir),
        "requiresElevation": target == "existing-nixos",
        "runInTerminal": True,
        "target": target,
    }


def _plan(repo: Path, ir_path: Path) -> dict[str, Any]:
    ir = load_ir(ir_path)
    return {"command": "plan", "ok": True, "plan": _make_plan(repo, ir)}


def _apply(
    repo: Path,
    ir_path: Path,
    timeout: float,
    json_output: bool,
    runner: Runner,
) -> dict[str, Any]:
    with exclusive_lock(ir_path, timeout):
        ir = load_ir(ir_path)
        plan = _make_plan(repo, ir)
        try:
            if json_output:
                completed = runner(
                    plan["argv"],
                    cwd=repo,
                    check=False,
                    shell=False,
                    text=True,
                    capture_output=True,
                )
            else:
                completed = runner(
                    plan["argv"], cwd=repo, check=False, shell=False, text=True
                )
        except OSError as exc:
            raise ConfigCtlError(
                "exec-failed", f"no se pudo iniciar install.sh: {exc}", exit_code=1
            ) from exc
    return {
        "command": "apply",
        "exitCode": completed.returncode,
        "ok": completed.returncode == 0,
        "plan": plan,
        "stderr": completed.stderr if json_output else "",
        "stdout": completed.stdout if json_output else "",
    }


HELP_SUMMARIES = {
    "status": "Muestra el IR efectivo; si falta el archivo, muestra defaults sin escribirlos.",
    "init": "Crea holodeck.local.json de forma atómica con defaults seguros.",
    "set": "Actualiza una clave allowlisted; inicializa el IR si todavía no existe.",
    "plan": "Valida el IR y devuelve el argv literal, sin ejecutar nada.",
    "apply": "Bloquea el IR y ejecuta install.sh por argv, sin shell ni sudo propio.",
    "action": "Ejecuta una acción integrada allowlisted por argv y en una terminal visible.",
}


def _json_help(topic: str | None) -> dict[str, Any]:
    if topic:
        return {
            "command": "help",
            "ok": True,
            "summary": HELP_SUMMARIES[topic],
            "topic": topic,
        }
    return {
        "command": "help",
        "commands": HELP_SUMMARIES,
        "environment": {
            "ir": ENV_IR,
            "lockTimeout": ENV_LOCK_TIMEOUT,
            "repo": ENV_REPO,
        },
        "ok": True,
        "settable": {
            "appearance.theme.builtin": {"type": "non-empty-string"},
            **{key: {"allowed": list(values)} for key, values in SETTERS.items()},
        },
        "actions": list(ALL_ACTIONS),
    }


def _parse_args(argv: Sequence[str]) -> tuple[Parser, argparse.Namespace]:
    # Parse common options first so the CLI accepts them before or after the
    # subcommand, which keeps calls from QML/Luau simple and unambiguous.
    common = Parser(add_help=False)
    _add_common_options(common)
    common_args, remaining = common.parse_known_args(list(argv))

    parser = make_parser()
    parsed = parser.parse_args(remaining)
    parsed.repo = common_args.repo
    parsed.ir = common_args.ir
    parsed.lock_timeout = common_args.lock_timeout
    parsed.json = common_args.json
    return parser, parsed


def run(
    argv: Sequence[str],
    *,
    environ: dict[str, str] | None = None,
    stdout: TextIO | None = None,
    stderr: TextIO | None = None,
    runner: Runner = subprocess.run,
    input_fn: Callable[[str], str] = input,
) -> int:
    environment = dict(os.environ if environ is None else environ)
    out = sys.stdout if stdout is None else stdout
    err = sys.stderr if stderr is None else stderr
    json_requested = "--json" in argv
    command = next((item for item in argv if item in HELP_SUMMARIES or item == "help"), "help")

    if json_requested and any(item in {"-h", "--help"} for item in argv):
        topic = command if command in HELP_SUMMARIES else None
        _emit_json(out, _json_help(topic))
        return 0

    try:
        parser, args = _parse_args(argv)
        json_output = args.json
        command = args.command or "help"

        if command == "help":
            topic = getattr(args, "topic", None)
            if json_output:
                _emit_json(out, _json_help(topic))
            elif topic:
                parser.parse_args([topic, "--help"])
            else:
                parser.print_help(out)
            return 0

        repo, ir_path, timeout = _resolve_context(args, environment)
        if command == "status":
            result = _status(repo, ir_path, environment)
            text = (
                f"IR válido desde {result['source']}: {ir_path}"
                + ("" if result["exists"] else " (ejecutá `holodeckctl init` para guardarlo)")
            )
        elif command == "init":
            result = _init(ir_path, timeout, args.force)
            text = f"IR {'creado' if result['changed'] else 'ya existente'}: {ir_path}"
        elif command == "set":
            result = _set(ir_path, timeout, args.key, args.value)
            text = f"{args.key}={result['value']} ({'actualizado' if result['changed'] else 'sin cambios'})"
        elif command == "plan":
            result = _plan(repo, ir_path)
            text = "Ejecutaría: " + " ".join(result["plan"]["argv"])
        elif command == "apply":
            result = _apply(repo, ir_path, timeout, json_output, runner)
            text = (
                "Configuración aplicada."
                if result["ok"]
                else f"La instalación terminó con código {result['exitCode']}."
            )
        elif command == "action":
            if json_output:
                raise ConfigCtlError(
                    "usage",
                    "action no acepta --json porque ejecuta un flujo interactivo en terminal",
                )
            result = execute_action(
                args.name,
                environment,
                runner=runner,
                input_fn=input_fn,
                stdout=out,
            )
            text = (
                f"Acción completada: {args.name}"
                if result["ok"]
                else f"La acción terminó con código {result['exitCode']}: {args.name}"
            )
        else:  # pragma: no cover - argparse owns this invariant
            raise ConfigCtlError("usage", f"comando desconocido: {command}")

        _emit_result(out, json_output, result, text)
        return 0 if result["ok"] else int(result.get("exitCode", 1) or 1)
    except ConfigCtlError as exc:
        payload = {
            "command": command,
            "error": {"code": exc.code, "message": str(exc)},
            "ok": False,
        }
        if json_requested:
            _emit_json(out, payload)
        else:
            err.write(f"Error: {exc}\n")
        return exc.exit_code
    except KeyboardInterrupt:
        if json_requested:
            _emit_json(
                out,
                {
                    "command": command,
                    "error": {"code": "interrupted", "message": "operación cancelada"},
                    "ok": False,
                },
            )
        else:
            err.write("Operación cancelada.\n")
        return 130


def main(argv: Sequence[str] | None = None) -> int:
    return run(sys.argv[1:] if argv is None else argv)
