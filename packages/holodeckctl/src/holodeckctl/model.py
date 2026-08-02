from __future__ import annotations

import copy
import hashlib
import json
from collections.abc import Mapping
from typing import Any

from .errors import ConfigCtlError

SCHEMA_VERSION = 1

DEFAULT_IR: dict[str, Any] = {
    "schemaVersion": SCHEMA_VERSION,
    "deployment": {"target": "home-manager"},
    "desktop": {
        "compositor": "niri",
        "shell": "noctalia",
    },
    "appearance": {
        "theme": {
            "mode": "dark",
            "builtin": "Catppuccin",
        }
    },
}

SETTERS: dict[str, tuple[str, ...]] = {
    "deployment.target": ("home-manager", "existing-nixos"),
    "desktop.compositor": ("niri",),
    "desktop.shell": ("noctalia",),
    "appearance.theme.mode": ("dark", "light"),
}

ALL_SETTABLE_KEYS = (*SETTERS.keys(), "appearance.theme.builtin")


def default_ir() -> dict[str, Any]:
    return copy.deepcopy(DEFAULT_IR)


def _expect_object(value: Any, path: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise ConfigCtlError("invalid-ir", f"{path} debe ser un objeto")
    return value


def _expect_exact_keys(value: Mapping[str, Any], expected: set[str], path: str) -> None:
    actual = set(value)
    missing = sorted(expected - actual)
    unknown = sorted(actual - expected)
    if missing:
        raise ConfigCtlError(
            "invalid-ir", f"faltan claves en {path}: {', '.join(missing)}"
        )
    if unknown:
        raise ConfigCtlError(
            "invalid-ir", f"claves desconocidas en {path}: {', '.join(unknown)}"
        )


def _expect_allowed(value: Any, allowed: tuple[str, ...], path: str) -> str:
    if not isinstance(value, str) or value not in allowed:
        choices = ", ".join(allowed)
        raise ConfigCtlError("invalid-ir", f"{path} debe ser uno de: {choices}")
    return value


def validate_ir(value: Any) -> dict[str, Any]:
    root = _expect_object(value, "IR")
    _expect_exact_keys(
        root,
        {"schemaVersion", "deployment", "desktop", "appearance"},
        "IR",
    )

    version = root["schemaVersion"]
    if isinstance(version, bool) or not isinstance(version, int):
        raise ConfigCtlError("invalid-ir", "schemaVersion debe ser un entero")
    if version != SCHEMA_VERSION:
        raise ConfigCtlError(
            "unsupported-schema",
            f"schemaVersion {version} no está soportado; se esperaba {SCHEMA_VERSION}",
        )

    deployment = _expect_object(root["deployment"], "deployment")
    _expect_exact_keys(deployment, {"target"}, "deployment")
    target = _expect_allowed(
        deployment["target"], SETTERS["deployment.target"], "deployment.target"
    )

    desktop = _expect_object(root["desktop"], "desktop")
    _expect_exact_keys(desktop, {"compositor", "shell"}, "desktop")
    compositor = _expect_allowed(
        desktop["compositor"], SETTERS["desktop.compositor"], "desktop.compositor"
    )
    shell = _expect_allowed(
        desktop["shell"], SETTERS["desktop.shell"], "desktop.shell"
    )

    appearance = _expect_object(root["appearance"], "appearance")
    _expect_exact_keys(appearance, {"theme"}, "appearance")
    theme = _expect_object(appearance["theme"], "appearance.theme")
    _expect_exact_keys(theme, {"mode", "builtin"}, "appearance.theme")
    mode = _expect_allowed(
        theme["mode"], SETTERS["appearance.theme.mode"], "appearance.theme.mode"
    )
    builtin = theme["builtin"]
    if not isinstance(builtin, str) or not builtin.strip():
        raise ConfigCtlError(
            "invalid-ir", "appearance.theme.builtin debe ser un string no vacío"
        )
    if "\x00" in builtin or "\n" in builtin or "\r" in builtin:
        raise ConfigCtlError(
            "invalid-ir",
            "appearance.theme.builtin no puede contener NUL ni saltos de línea",
        )

    # Rebuild the object so callers never preserve custom Mapping subclasses or
    # unknown aliases after validation.
    return {
        "schemaVersion": SCHEMA_VERSION,
        "deployment": {"target": target},
        "desktop": {"compositor": compositor, "shell": shell},
        "appearance": {"theme": {"mode": mode, "builtin": builtin.strip()}},
    }


def set_value(ir: Mapping[str, Any], key: str, value: str) -> dict[str, Any]:
    normalized = validate_ir(ir)
    if key in SETTERS:
        allowed = SETTERS[key]
        if value not in allowed:
            raise ConfigCtlError(
                "invalid-value",
                f"valor inválido para {key}; opciones: {', '.join(allowed)}",
            )
    elif key == "appearance.theme.builtin":
        if not value.strip() or "\x00" in value or "\n" in value or "\r" in value:
            raise ConfigCtlError(
                "invalid-value", f"valor inválido para {key}; debe ser un string no vacío"
            )
        value = value.strip()
    else:
        raise ConfigCtlError(
            "unknown-key",
            f"clave no configurable: {key}; opciones: {', '.join(ALL_SETTABLE_KEYS)}",
        )

    first, second, *third = key.split(".")
    if third:
        normalized[first][second][third[0]] = value
    else:
        normalized[first][second] = value
    return validate_ir(normalized)


def canonical_json(ir: Mapping[str, Any]) -> str:
    normalized = validate_ir(ir)
    return json.dumps(normalized, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def digest_ir(ir: Mapping[str, Any]) -> str:
    digest = hashlib.sha256(canonical_json(ir).encode("utf-8")).hexdigest()
    return f"sha256:{digest}"
