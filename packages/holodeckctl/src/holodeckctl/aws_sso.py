from __future__ import annotations

import configparser
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol, TextIO
from urllib.parse import urlsplit

from .errors import ConfigCtlError

Runner = Callable[..., subprocess.CompletedProcess[str]]
Input = Callable[[str], str]
Which = Callable[..., str | None]

MANAGED_BEGIN = "# >>> holodeck aws sso >>>"
MANAGED_END = "# <<< holodeck aws sso <<<"
DEFAULT_SESSION_NAME = "holodeck"
ALIAS_SCHEMA_VERSION = 3
CATALOG_SCHEMA_VERSION = 3
SINGLE_REGION_SCHEMA_VERSION = 2
LEGACY_SCHEMA_VERSION = 1
ALIAS_REQUEST_NAME = "aws-alias-request.json"
MAX_REGIONS_PER_ASSIGNMENT = 32
DEFAULT_CLIENT_REGIONS = ("us-east-1", "us-east-2")
SESSION_NAME_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
REGION_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)+-[0-9]+$")
PROFILE_KEY_RE = re.compile(r"^[a-f0-9]{24}$")
ALIAS_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,79}$")


class Paginator(Protocol):
    def paginate(self, **kwargs: Any) -> Any: ...


class SsoClient(Protocol):
    def get_paginator(self, operation_name: str) -> Paginator: ...


SsoClientFactory = Callable[[str], SsoClient]


@dataclass(frozen=True)
class AwsSsoSettings:
    start_url: str
    sso_region: str
    session_name: str
    manage_session: bool


@dataclass(frozen=True)
class AwsSsoProfile:
    name: str
    key: str
    account_id: str
    account_name: str
    role_name: str
    region: str
    alias: str
    default_alias: str
    suggested_alias: str


@dataclass(frozen=True)
class AwsSsoAssignment:
    key: str
    account_id: str
    account_name: str
    role_name: str
    regions: tuple[str, ...]
    suggested_regions: tuple[str, ...]
    alias: str
    default_alias: str
    suggested_alias: str


def _home(environ: Mapping[str, str]) -> Path:
    return Path(environ.get("HOME", str(Path.home()))).expanduser()


def _aws_config_path(environ: Mapping[str, str]) -> Path:
    return Path(environ.get("AWS_CONFIG_FILE", str(_home(environ) / ".aws" / "config")))


def _config_home(environ: Mapping[str, str]) -> Path:
    return Path(
        environ.get("XDG_CONFIG_HOME", str(_home(environ) / ".config"))
    ).expanduser()


def _state_home(environ: Mapping[str, str]) -> Path:
    return Path(
        environ.get("XDG_STATE_HOME", str(_home(environ) / ".local" / "state"))
    ).expanduser()


def _aliases_path(environ: Mapping[str, str]) -> Path:
    return _config_home(environ) / "holodeck" / "aws-aliases.json"


def _catalog_path(environ: Mapping[str, str]) -> Path:
    return _state_home(environ) / "holodeck" / "aws-sso-catalog.json"


def _alias_request_path(environ: Mapping[str, str]) -> Path:
    if environ.get("NOCTALIA_STATE_HOME"):
        root = Path(environ["NOCTALIA_STATE_HOME"]).expanduser()
    else:
        root = _state_home(environ)
    return (
        root
        / "noctalia"
        / "plugins"
        / "data"
        / "holodeck"
        / "control"
        / ALIAS_REQUEST_NAME
    )


def _command_path(name: str, environ: Mapping[str, str], which: Which) -> str | None:
    try:
        return which(name, path=environ.get("PATH"))
    except TypeError:
        return which(name)


def _read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return ""
    except OSError as exc:
        raise ConfigCtlError(
            "aws-config-read-failed", f"no se pudo leer {path}: {exc}"
        ) from exc


def _read_json(path: Path, label: str) -> Any:
    try:
        if path.stat().st_size > 131_072:
            raise ConfigCtlError("invalid-aws-aliases", f"{label} es demasiado grande")
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    except ConfigCtlError:
        raise
    except (OSError, json.JSONDecodeError) as exc:
        raise ConfigCtlError(
            "invalid-aws-aliases", f"no se pudo leer {label}: {exc}"
        ) from exc


def _write_private_json(path: Path, payload: Mapping[str, Any]) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    content = json.dumps(
        payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ) + "\n"
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        directory_descriptor = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def _split_managed_block(text: str) -> tuple[str, str]:
    begin_count = text.count(MANAGED_BEGIN)
    end_count = text.count(MANAGED_END)
    if begin_count == 0 and end_count == 0:
        return text, ""
    if begin_count != 1 or end_count != 1:
        raise ConfigCtlError(
            "invalid-aws-config",
            "el bloque AWS administrado por Holodeck está incompleto o duplicado",
        )

    begin = text.index(MANAGED_BEGIN)
    end = text.index(MANAGED_END, begin) + len(MANAGED_END)
    before = text[:begin].rstrip()
    after = text[end:].lstrip("\r\n")
    parts = [part for part in (before, after.rstrip()) if part]
    base = "\n\n".join(parts)
    if base:
        base += "\n"
    return base, text[begin:end]


def _parse_config(text: str) -> configparser.RawConfigParser:
    parser = configparser.RawConfigParser(interpolation=None, strict=True)
    if not text.strip():
        return parser
    try:
        parser.read_string(text)
    except configparser.Error as exc:
        raise ConfigCtlError(
            "invalid-aws-config", f"~/.aws/config no es un INI válido: {exc}"
        ) from exc
    return parser


def _normalized_url(value: str) -> str:
    candidate = value.strip().rstrip("/")
    parsed = urlsplit(candidate)
    if (
        parsed.scheme != "https"
        or not parsed.netloc
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
    ):
        raise ConfigCtlError(
            "invalid-aws-sso-url", "la URL de AWS SSO debe ser una URL HTTPS sin credenciales ni query"
        )
    return candidate


def _validated_region(value: str, label: str) -> str:
    candidate = value.strip().lower()
    if not REGION_RE.fullmatch(candidate):
        raise ConfigCtlError(
            "invalid-aws-region", f"{label} no parece una región AWS válida: {value}"
        )
    return candidate


def _validated_regions(
    value: Any, label: str, *, allow_empty: bool
) -> tuple[str, ...]:
    if not isinstance(value, list) or len(value) > MAX_REGIONS_PER_ASSIGNMENT:
        raise ConfigCtlError(
            "invalid-aws-region",
            f"{label} debe ser una lista de hasta {MAX_REGIONS_PER_ASSIGNMENT} regiones AWS",
        )
    regions: list[str] = []
    seen: set[str] = set()
    for index, raw_region in enumerate(value, start=1):
        if not isinstance(raw_region, str):
            raise ConfigCtlError(
                "invalid-aws-region", f"{label} contiene una región inválida"
            )
        region = _validated_region(raw_region, f"{label} #{index}")
        if region not in seen:
            seen.add(region)
            regions.append(region)
    if not regions and not allow_empty:
        raise ConfigCtlError(
            "missing-aws-region",
            f"{label} requiere al menos una región cliente AWS",
        )
    return tuple(regions)


def _validated_session_name(value: str) -> str:
    candidate = value.strip()
    if not SESSION_NAME_RE.fullmatch(candidate):
        raise ConfigCtlError(
            "invalid-aws-session",
            "el nombre de sesión AWS sólo puede contener letras, números, guion y guion bajo",
        )
    return candidate


def _prompt_value(input_fn: Input, label: str, default: str | None = None) -> str:
    suffix = f" [{default}]" if default else ""
    value = input_fn(f"{label}{suffix}: ").strip()
    if value:
        return value
    if default:
        return default
    raise ConfigCtlError("missing-aws-setting", f"{label} es obligatorio")


def _session_name(section: str) -> str | None:
    prefix = "sso-session "
    if section.startswith(prefix):
        name = section[len(prefix) :].strip()
        return name or None
    return None


def _resolve_settings(
    environ: Mapping[str, str], *, input_fn: Input, stdout: TextIO
) -> tuple[AwsSsoSettings, str, str]:
    config_path = _aws_config_path(environ)
    original = _read_text(config_path)
    base, managed = _split_managed_block(original)
    parser = _parse_config(original)

    sessions: list[tuple[str, str, str, bool]] = []
    for section in parser.sections():
        name = _session_name(section)
        if name is None:
            continue
        existing_url = parser.get(section, "sso_start_url", fallback="").strip()
        existing_region = parser.get(section, "sso_region", fallback="").strip()
        if not existing_url or not existing_region:
            continue
        try:
            sessions.append(
                (
                    name,
                    _normalized_url(existing_url),
                    _validated_region(existing_region, "sso_region"),
                    f"[sso-session {name}]" in managed,
                )
            )
        except ConfigCtlError:
            continue

    reusable_session = next((session for session in sessions if session[3]), None)
    if reusable_session is None:
        reusable_session = next(
            (session for session in sessions if session[0] == DEFAULT_SESSION_NAME),
            sessions[0] if sessions else None,
        )

    if reusable_session is not None:
        session_name, start_url, sso_region, manage_session = reusable_session
        stdout.write(f"Reutilizando la sesión SSO: {session_name} ({sso_region})\n")
    else:
        start_url = _normalized_url(
            _prompt_value(input_fn, "AWS SSO start/issuer URL")
        )
        session_name = DEFAULT_SESSION_NAME
        configured_region = (
            environ.get("AWS_REGION") or environ.get("AWS_DEFAULT_REGION") or ""
        ).strip()
        if configured_region:
            sso_region = _validated_region(configured_region, "sso_region")
        else:
            sso_region = _validated_region(
                _prompt_value(input_fn, "Región de AWS IAM Identity Center"),
                "sso_region",
            )
        manage_session = True

    settings = AwsSsoSettings(
        start_url=start_url,
        sso_region=sso_region,
        session_name=_validated_session_name(session_name),
        manage_session=manage_session,
    )

    base_parser = _parse_config(base)
    session_section = f"sso-session {settings.session_name}"
    if settings.manage_session and base_parser.has_section(session_section):
        raise ConfigCtlError(
            "aws-session-conflict",
            f"la sección [{session_section}] ya existe fuera del bloque administrado por Holodeck",
        )
    return settings, base, managed


def _safe_value(value: str, label: str) -> str:
    candidate = value.strip()
    if not candidate or any(character in candidate for character in ("\n", "\r", "\x00")):
        raise ConfigCtlError("invalid-aws-response", f"AWS devolvió un {label} inválido")
    return candidate


def _slug(value: str) -> str:
    normalized = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return normalized[:80].rstrip("-")


ENVIRONMENT_ALIASES = {
    "development": "dev",
    "develop": "dev",
    "dev": "dev",
    "production": "prd",
    "prod": "prd",
    "prd": "prd",
    "staging": "stg",
    "stage": "stg",
    "stg": "stg",
    "quality": "qa",
    "qa": "qa",
    "uat": "uat",
    "sandbox": "sbx",
    "sbx": "sbx",
    "nop": "nop",
}
ROLE_ALIASES = {
    "administrator": "admin",
    "administratoraccess": "admin",
    "awsreadonlyaccess": "ro",
    "developer": "dev",
    "developeraccess": "dev",
    "poweruser": "power",
    "poweruseraccess": "power",
    "readonly": "ro",
    "readonlyaccess": "ro",
    "securityaudit": "audit",
}
NOISE_WORDS = {"aws", "nv", "role"}


def _words(value: str) -> list[str]:
    separated = re.sub(r"([a-z0-9])([A-Z])", r"\1-\2", value.strip())
    return [word.lower() for word in re.findall(r"[A-Za-z0-9]+", separated)]


def _abbreviate(words: list[str], fallback: str) -> str:
    meaningful = [word for word in words if word and word not in NOISE_WORDS]
    if not meaningful:
        return fallback
    if len(meaningful) == 1:
        word = meaningful[0]
        return word if len(word) <= 5 else word[:5]
    initials = "".join(word[0] for word in meaningful[:5])
    return initials if len(initials) >= 2 else meaningful[0][:5]


def _region_alias(region: str) -> str:
    parts = region.split("-")
    directions = {
        "central": "c",
        "east": "e",
        "north": "n",
        "northeast": "ne",
        "northwest": "nw",
        "south": "s",
        "southeast": "se",
        "southwest": "sw",
        "west": "w",
    }
    if len(parts) == 3:
        return f"{parts[0]}{directions.get(parts[1], parts[1][0])}{parts[2]}"
    if len(parts) == 4 and parts[1] == "gov":
        return f"{parts[0]}g{directions.get(parts[2], parts[2][0])}{parts[3]}"
    return "".join(part if part.isdigit() else part[:2] for part in parts)


def _default_alias(account_name: str, account_id: str, role_name: str) -> str:
    account_part = _slug(account_name) or account_id
    role_part = _slug(role_name) or "role"
    return f"{account_part}-{role_part}"[:80].rstrip("-")


def _recommended_alias(account_name: str, account_id: str, role_name: str) -> str:
    account_words = _words(account_name)
    environment = (
        next(
            (
                ENVIRONMENT_ALIASES[word]
                for word in account_words
                if word in ENVIRONMENT_ALIASES
            ),
            "",
        )
        if len(account_words) > 1
        else ""
    )
    account_core = [
        word
        for word in account_words
        if (not environment or word not in ENVIRONMENT_ALIASES)
        and word not in NOISE_WORDS
    ]
    account_alias = _abbreviate(account_core, account_id[-4:])

    role_words = _words(role_name)
    collapsed_role = "".join(role_words)
    role_alias = ROLE_ALIASES.get(collapsed_role)
    if role_alias is None:
        role_core = [
            word
            for word in role_words
            if word not in ENVIRONMENT_ALIASES
            and word not in NOISE_WORDS
            and word != "access"
        ]
        role_alias = _abbreviate(role_core, "role")

    return "-".join(
        part for part in (account_alias, environment, role_alias) if part
    )[:64].rstrip("-")


def _profile_key(session_name: str, account_id: str, role_name: str) -> str:
    """Return a stable assignment key that survives target-region changes."""
    identity = "\x00".join((session_name, account_id, role_name))
    return hashlib.sha256(identity.encode("utf-8")).hexdigest()[:24]


def _legacy_profile_key(
    session_name: str, account_id: str, role_name: str, region: str
) -> str:
    identity = "\x00".join((session_name, account_id, role_name, region))
    return hashlib.sha256(identity.encode("utf-8")).hexdigest()[:24]


def _alias_slug(value: str, label: str) -> str:
    candidate = _slug(value)
    if not ALIAS_RE.fullmatch(candidate):
        raise ConfigCtlError(
            "invalid-aws-alias",
            f"{label} debe producir entre 1 y 80 caracteres alfanuméricos o guiones",
        )
    return candidate


def _validated_alias(value: str, label: str) -> str:
    return _alias_slug(value, label)


def _unique_profile_name(
    alias: str,
    account_id: str,
    region: str,
    reserved: set[str],
) -> str:
    region_part = _region_alias(region)

    def with_suffix(*parts: str) -> str:
        suffix = f"-{'-'.join(parts)}"
        return f"{alias[: 120 - len(suffix)].rstrip('-')}{suffix}"

    base = with_suffix(region_part)
    candidate = base
    if candidate in reserved:
        candidate = with_suffix(region_part, account_id[-4:])
    suffix = 2
    while candidate in reserved:
        candidate = with_suffix(region_part, account_id[-4:], str(suffix))
        suffix += 1
    reserved.add(candidate)
    return candidate


def _catalog_preferences(
    catalog: Mapping[str, Any] | None,
) -> dict[str, dict[str, Any]]:
    if catalog is None:
        return {}
    return {
        assignment["key"]: {
            "alias": assignment["alias"],
            "regions": list(assignment["regions"]),
            "suggestedRegions": list(assignment["suggestedRegions"]),
        }
        for assignment in catalog["assignments"]
    }


def _load_preferences(
    environ: Mapping[str, str],
    catalog: Mapping[str, Any] | None,
) -> dict[str, dict[str, Any]]:
    payload = _read_json(_aliases_path(environ), "el archivo local de alias AWS")
    preferences = _catalog_preferences(catalog)
    if payload is None:
        return preferences
    if not isinstance(payload, dict):
        raise ConfigCtlError(
            "invalid-aws-aliases", "el archivo local de alias AWS tiene una versión inválida"
        )

    schema_version = payload.get("schemaVersion")
    if schema_version == LEGACY_SCHEMA_VERSION:
        raw_aliases = payload.get("aliases")
        if not isinstance(raw_aliases, dict):
            raise ConfigCtlError(
                "invalid-aws-aliases", "el archivo local de alias AWS no contiene un mapa válido"
            )
        validated_aliases: dict[str, str] = {}
        for raw_key, raw_alias in raw_aliases.items():
            if not isinstance(raw_key, str) or not PROFILE_KEY_RE.fullmatch(raw_key):
                raise ConfigCtlError(
                    "invalid-aws-aliases", "el archivo local contiene una clave de perfil inválida"
                )
            if not isinstance(raw_alias, str):
                raise ConfigCtlError(
                    "invalid-aws-aliases", "el archivo local contiene un alias AWS inválido"
                )
            validated_aliases[raw_key] = _alias_slug(raw_alias, f"alias {raw_key}")

        if catalog is not None:
            session_name = catalog["sessionName"]
            for assignment in catalog["assignments"]:
                candidate_regions = (
                    assignment["suggestedRegions"] or assignment["regions"]
                )
                for region in candidate_regions:
                    legacy_key = _legacy_profile_key(
                        session_name,
                        assignment["accountId"],
                        assignment["roleName"],
                        region,
                    )
                    if legacy_key in validated_aliases:
                        preferences[assignment["key"]]["alias"] = validated_aliases[
                            legacy_key
                        ]
                        break
        return preferences

    if schema_version not in {
        SINGLE_REGION_SCHEMA_VERSION,
        ALIAS_SCHEMA_VERSION,
    }:
        raise ConfigCtlError(
            "invalid-aws-aliases", "el archivo local de alias AWS tiene una versión inválida"
        )
    raw_profiles = payload.get("profiles")
    if not isinstance(raw_profiles, dict):
        raise ConfigCtlError(
            "invalid-aws-aliases", "el archivo local de alias AWS no contiene preferencias válidas"
        )
    for raw_key, raw_preference in raw_profiles.items():
        if not isinstance(raw_key, str) or not PROFILE_KEY_RE.fullmatch(raw_key):
            raise ConfigCtlError(
                "invalid-aws-aliases", "el archivo local contiene una clave de perfil inválida"
            )
        if not isinstance(raw_preference, dict):
            raise ConfigCtlError(
                "invalid-aws-aliases", "el archivo local contiene preferencias AWS inválidas"
            )
        if schema_version == SINGLE_REGION_SCHEMA_VERSION:
            if (
                set(raw_preference) != {"alias", "region"}
                or not isinstance(raw_preference.get("alias"), str)
                or not isinstance(raw_preference.get("region"), str)
            ):
                raise ConfigCtlError(
                    "invalid-aws-aliases",
                    "el archivo local contiene preferencias AWS v2 inválidas",
                )
            inherited_region = _validated_region(
                raw_preference["region"], f"región heredada {raw_key}"
            )
            preferences[raw_key] = {
                "alias": _alias_slug(raw_preference["alias"], f"alias {raw_key}"),
                "regions": list(DEFAULT_CLIENT_REGIONS),
                "suggestedRegions": (
                    []
                    if inherited_region in DEFAULT_CLIENT_REGIONS
                    else [inherited_region]
                ),
            }
            continue

        if (
            set(raw_preference) != {"alias", "regions", "suggestedRegions"}
            or not isinstance(raw_preference.get("alias"), str)
        ):
            raise ConfigCtlError(
                "invalid-aws-aliases",
                "el archivo local contiene preferencias AWS v3 inválidas",
            )
        regions = _validated_regions(
            raw_preference["regions"], f"regiones {raw_key}", allow_empty=True
        )
        suggested_regions = tuple(
            region
            for region in _validated_regions(
                raw_preference["suggestedRegions"],
                f"regiones sugeridas {raw_key}",
                allow_empty=True,
            )
            if region not in regions
        )
        preferences[raw_key] = {
            "alias": _alias_slug(raw_preference["alias"], f"alias {raw_key}"),
            "regions": list(regions),
            "suggestedRegions": list(suggested_regions),
        }
    return preferences


def _preferences_payload(assignments: list[AwsSsoAssignment]) -> dict[str, Any]:
    return {
        "profiles": {
            assignment.key: {
                "alias": assignment.alias,
                "regions": list(assignment.regions),
                "suggestedRegions": list(assignment.suggested_regions),
            }
            for assignment in assignments
        },
        "schemaVersion": ALIAS_SCHEMA_VERSION,
    }


def _profile_payload(profile: AwsSsoProfile) -> dict[str, Any]:
    return {
        "accountName": profile.account_name,
        "alias": profile.alias,
        "custom": profile.alias != profile.default_alias,
        "defaultAlias": profile.default_alias,
        "key": profile.key,
        "name": profile.name,
        "region": profile.region,
        "regionAlias": _region_alias(profile.region),
        "roleName": profile.role_name,
        "suggestedAlias": profile.suggested_alias,
    }


def _assignment_payload(
    assignment: AwsSsoAssignment, profiles: list[AwsSsoProfile]
) -> dict[str, Any]:
    return {
        "accountName": assignment.account_name,
        "alias": assignment.alias,
        "custom": assignment.alias != assignment.default_alias,
        "defaultAlias": assignment.default_alias,
        "key": assignment.key,
        "pending": not assignment.regions,
        "profiles": [
            {
                "name": profile.name,
                "region": profile.region,
                "regionAlias": _region_alias(profile.region),
            }
            for profile in profiles
            if profile.key == assignment.key
        ],
        "regions": list(assignment.regions),
        "roleName": assignment.role_name,
        "suggestedAlias": assignment.suggested_alias,
        "suggestedRegions": list(assignment.suggested_regions),
    }


def _catalog_payload(
    settings: AwsSsoSettings, assignments: list[AwsSsoAssignment]
) -> dict[str, Any]:
    return {
        "assignments": [
            {
                **_assignment_payload(assignment, []),
                "accountId": assignment.account_id,
            }
            for assignment in assignments
        ],
        "schemaVersion": CATALOG_SCHEMA_VERSION,
        "sessionName": settings.session_name,
    }


def _load_catalog(environ: Mapping[str, str]) -> dict[str, Any] | None:
    payload = _read_json(_catalog_path(environ), "el catálogo local de perfiles AWS")
    if payload is None:
        return None
    if not isinstance(payload, dict) or payload.get("schemaVersion") not in {
        LEGACY_SCHEMA_VERSION,
        SINGLE_REGION_SCHEMA_VERSION,
        CATALOG_SCHEMA_VERSION,
    }:
        raise ConfigCtlError(
            "invalid-aws-aliases", "el catálogo local de perfiles AWS tiene una versión inválida"
        )
    schema_version = payload["schemaVersion"]
    session_name = payload.get("sessionName")
    if not isinstance(session_name, str):
        raise ConfigCtlError(
            "invalid-aws-aliases", "el catálogo local de perfiles AWS está incompleto"
        )
    _validated_session_name(session_name)

    if schema_version == CATALOG_SCHEMA_VERSION:
        raw_assignments = payload.get("assignments")
        if not isinstance(raw_assignments, list) or len(raw_assignments) > 10_000:
            raise ConfigCtlError(
                "invalid-aws-aliases",
                "el catálogo local de perfiles AWS no contiene asignaciones válidas",
            )
        required = {
            "accountId",
            "accountName",
            "alias",
            "defaultAlias",
            "key",
            "regions",
            "roleName",
            "suggestedAlias",
            "suggestedRegions",
        }
        assignments: list[dict[str, Any]] = []
        seen_keys: set[str] = set()
        for raw_assignment in raw_assignments:
            if (
                not isinstance(raw_assignment, dict)
                or not required.issubset(raw_assignment)
            ):
                raise ConfigCtlError(
                    "invalid-aws-aliases",
                    "el catálogo local contiene una asignación incompleta",
                )
            string_fields = required - {"regions", "suggestedRegions"}
            if any(
                not isinstance(raw_assignment[field], str)
                for field in string_fields
            ):
                raise ConfigCtlError(
                    "invalid-aws-aliases",
                    "el catálogo local contiene metadatos inválidos",
                )
            account_id = _safe_value(raw_assignment["accountId"], "accountId")
            if not re.fullmatch(r"[0-9]{12}", account_id):
                raise ConfigCtlError(
                    "invalid-aws-aliases",
                    "el catálogo local contiene un accountId inválido",
                )
            account_name = _safe_value(raw_assignment["accountName"], "accountName")
            role_name = _safe_value(raw_assignment["roleName"], "roleName")
            key = raw_assignment["key"]
            if (
                not PROFILE_KEY_RE.fullmatch(key)
                or key != _profile_key(session_name, account_id, role_name)
                or key in seen_keys
            ):
                raise ConfigCtlError(
                    "invalid-aws-aliases",
                    "el catálogo local contiene una identidad inconsistente",
                )
            seen_keys.add(key)
            default_alias = _alias_slug(raw_assignment["defaultAlias"], "defaultAlias")
            suggested_alias = _alias_slug(
                raw_assignment["suggestedAlias"], "suggestedAlias"
            )
            if default_alias != _default_alias(account_name, account_id, role_name):
                raise ConfigCtlError(
                    "invalid-aws-aliases",
                    "el catálogo local contiene un alias original inconsistente",
                )
            if suggested_alias != _recommended_alias(account_name, account_id, role_name):
                raise ConfigCtlError(
                    "invalid-aws-aliases",
                    "el catálogo local contiene una recomendación inconsistente",
                )
            regions = _validated_regions(
                raw_assignment["regions"], f"regiones {key}", allow_empty=True
            )
            suggested_regions = tuple(
                region
                for region in _validated_regions(
                    raw_assignment["suggestedRegions"],
                    f"regiones sugeridas {key}",
                    allow_empty=True,
                )
                if region not in regions
            )
            assignments.append(
                {
                    "accountId": account_id,
                    "accountName": account_name,
                    "alias": _alias_slug(raw_assignment["alias"], "alias"),
                    "defaultAlias": default_alias,
                    "key": key,
                    "regions": list(regions),
                    "roleName": role_name,
                    "suggestedAlias": suggested_alias,
                    "suggestedRegions": list(suggested_regions),
                }
            )
        return {
            "assignments": assignments,
            "schemaVersion": CATALOG_SCHEMA_VERSION,
            "sessionName": session_name,
            "sourceSchemaVersion": schema_version,
        }

    region = payload.get("defaultRegion")
    raw_profiles = payload.get("profiles")
    if not isinstance(region, str):
        raise ConfigCtlError(
            "invalid-aws-aliases", "el catálogo local de perfiles AWS está incompleto"
        )
    _validated_region(region, "región heredada del catálogo")
    if not isinstance(raw_profiles, list) or len(raw_profiles) > 10_000:
        raise ConfigCtlError(
            "invalid-aws-aliases", "el catálogo local de perfiles AWS no contiene perfiles válidos"
        )

    required_strings = {
        "accountId",
        "accountName",
        "alias",
        "defaultAlias",
        "key",
        "name",
        "region",
        "regionAlias",
        "roleName",
        "suggestedAlias",
    }
    assignments_by_key: dict[str, dict[str, Any]] = {}
    for raw_profile in raw_profiles:
        if not isinstance(raw_profile, dict) or not required_strings.issubset(raw_profile):
            raise ConfigCtlError(
                "invalid-aws-aliases", "el catálogo local contiene un perfil incompleto"
            )
        if any(not isinstance(raw_profile[key], str) for key in required_strings):
            raise ConfigCtlError(
                "invalid-aws-aliases", "el catálogo local contiene metadatos inválidos"
            )
        account_id = _safe_value(raw_profile["accountId"], "accountId")
        if not re.fullmatch(r"[0-9]{12}", account_id):
            raise ConfigCtlError(
                "invalid-aws-aliases", "el catálogo local contiene un accountId inválido"
            )
        raw_key = raw_profile["key"]
        profile_region = _validated_region(raw_profile["region"], "región de perfil")
        account_name = _safe_value(raw_profile["accountName"], "accountName")
        role_name = _safe_value(raw_profile["roleName"], "roleName")
        if not PROFILE_KEY_RE.fullmatch(raw_key):
            raise ConfigCtlError(
                "invalid-aws-aliases", "el catálogo local contiene una clave inválida"
            )
        expected_key = (
            _legacy_profile_key(session_name, account_id, role_name, profile_region)
            if schema_version == LEGACY_SCHEMA_VERSION
            else _profile_key(session_name, account_id, role_name)
        )
        if raw_key != expected_key:
            raise ConfigCtlError(
                "invalid-aws-aliases", "el catálogo local contiene una identidad inconsistente"
            )
        key = _profile_key(session_name, account_id, role_name)
        if raw_profile["regionAlias"] != _region_alias(profile_region):
            raise ConfigCtlError(
                "invalid-aws-aliases", "el catálogo local contiene una región abreviada inválida"
            )
        alias = _alias_slug(raw_profile["alias"], "alias")
        default_alias = _alias_slug(raw_profile["defaultAlias"], "defaultAlias")
        suggested_alias = _alias_slug(
            raw_profile["suggestedAlias"], "suggestedAlias"
        )
        if default_alias != _default_alias(account_name, account_id, role_name):
            raise ConfigCtlError(
                "invalid-aws-aliases", "el catálogo local contiene un alias original inconsistente"
            )
        if suggested_alias != _recommended_alias(account_name, account_id, role_name):
            raise ConfigCtlError(
                "invalid-aws-aliases", "el catálogo local contiene una recomendación inconsistente"
            )
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,119}", raw_profile["name"]):
            raise ConfigCtlError(
                "invalid-aws-aliases", "el catálogo local contiene un nombre de perfil inválido"
            )
        assignment = assignments_by_key.get(key)
        if assignment is None:
            assignment = {
                "accountId": account_id,
                "accountName": account_name,
                "alias": alias,
                "defaultAlias": default_alias,
                "key": key,
                "regions": list(DEFAULT_CLIENT_REGIONS),
                "roleName": role_name,
                "suggestedAlias": suggested_alias,
                "suggestedRegions": [],
            }
            assignments_by_key[key] = assignment
        elif (
            assignment["accountId"] != account_id
            or assignment["roleName"] != role_name
            or assignment["accountName"] != account_name
        ):
            raise ConfigCtlError(
                "invalid-aws-aliases",
                "el catálogo heredado repite una identidad con metadatos incompatibles",
            )
        if profile_region not in assignment["suggestedRegions"]:
            assignment["suggestedRegions"].append(profile_region)
    return {
        "assignments": list(assignments_by_key.values()),
        "schemaVersion": CATALOG_SCHEMA_VERSION,
        "sessionName": session_name,
        "sourceSchemaVersion": schema_version,
    }


def _assignments_from_catalog(
    catalog: Mapping[str, Any],
    preferences: Mapping[str, Mapping[str, Any]],
) -> list[AwsSsoAssignment]:
    assignments: list[AwsSsoAssignment] = []
    for item in catalog["assignments"]:
        preference = preferences.get(item["key"], {})
        raw_regions = preference.get("regions", item["regions"])
        if raw_regions == []:
            raw_regions = list(DEFAULT_CLIENT_REGIONS)
        regions = _validated_regions(
            raw_regions,
            f"regiones {item['key']}",
            allow_empty=True,
        )
        suggested_regions = tuple(
            region
            for region in _validated_regions(
                preference.get("suggestedRegions", item["suggestedRegions"]),
                f"regiones sugeridas {item['key']}",
                allow_empty=True,
            )
            if region not in regions
        )
        assignments.append(
            AwsSsoAssignment(
                key=item["key"],
                account_id=item["accountId"],
                account_name=item["accountName"],
                role_name=item["roleName"],
                regions=regions,
                suggested_regions=suggested_regions,
                alias=_alias_slug(
                    preference.get("alias", item["defaultAlias"]),
                    f"alias {item['key']}",
                ),
                default_alias=item["defaultAlias"],
                suggested_alias=item["suggestedAlias"],
            )
        )
    return assignments


def _reserved_profile_names(base: str) -> set[str]:
    parser = _parse_config(base)
    reserved = {
        section[len("profile ") :].strip()
        for section in parser.sections()
        if section.startswith("profile ")
    }
    if parser.has_section("default"):
        reserved.add("default")
    return reserved


def _managed_profile_state(environ: Mapping[str, str]) -> list[tuple[str, str]]:
    _base, managed = _split_managed_block(_read_text(_aws_config_path(environ)))
    parser = _parse_config(managed)
    state: list[tuple[str, str]] = []
    for section in parser.sections():
        if not section.startswith("profile "):
            continue
        name = section[len("profile ") :].strip()
        region = _validated_region(
            parser.get(section, "region", fallback=""),
            f"región del perfil existente {name}",
        )
        state.append((name, region))
    return sorted(state)


def _expand_profiles(
    assignments: list[AwsSsoAssignment], reserved: set[str]
) -> list[AwsSsoProfile]:
    profiles: list[AwsSsoProfile] = []
    for assignment in assignments:
        for region in assignment.regions:
            profiles.append(
                AwsSsoProfile(
                    name=_unique_profile_name(
                        assignment.alias,
                        assignment.account_id,
                        region,
                        reserved,
                    ),
                    key=assignment.key,
                    account_id=assignment.account_id,
                    account_name=assignment.account_name,
                    role_name=assignment.role_name,
                    region=region,
                    alias=assignment.alias,
                    default_alias=assignment.default_alias,
                    suggested_alias=assignment.suggested_alias,
                )
            )
    return profiles


def aws_alias_profiles(environ: Mapping[str, str]) -> list[dict[str, Any]]:
    try:
        catalog = _load_catalog(environ)
    except ConfigCtlError:
        return []
    if catalog is None:
        return []
    try:
        base, _managed = _split_managed_block(
            _read_text(_aws_config_path(environ))
        )
        assignments = _assignments_from_catalog(
            catalog, _catalog_preferences(catalog)
        )
        profiles = _expand_profiles(assignments, _reserved_profile_names(base))
    except ConfigCtlError:
        return []
    return [
        _assignment_payload(assignment, profiles) for assignment in assignments
    ]


def _discover_assignments(
    client: SsoClient,
    access_token: str,
    session_name: str,
    preferences: Mapping[str, Mapping[str, Any]],
) -> tuple[list[AwsSsoAssignment], int]:
    accounts: dict[str, str] = {}
    try:
        account_pages = client.get_paginator("list_accounts").paginate(
            accessToken=access_token
        )
        for page in account_pages:
            for raw_account in page.get("accountList", []):
                account_id = _safe_value(str(raw_account.get("accountId", "")), "accountId")
                if not re.fullmatch(r"[0-9]{12}", account_id):
                    raise ConfigCtlError(
                        "invalid-aws-response", "AWS devolvió un accountId inválido"
                    )
                account_name = _safe_value(
                    str(raw_account.get("accountName") or account_id), "accountName"
                )
                accounts[account_id] = account_name

        assignments: list[AwsSsoAssignment] = []
        role_paginator = client.get_paginator("list_account_roles")
        for account_id, account_name in sorted(
            accounts.items(), key=lambda item: (item[1].lower(), item[0])
        ):
            roles: set[str] = set()
            for page in role_paginator.paginate(
                accessToken=access_token, accountId=account_id
            ):
                for raw_role in page.get("roleList", []):
                    roles.add(_safe_value(str(raw_role.get("roleName", "")), "roleName"))
            for role_name in sorted(roles, key=str.lower):
                key = _profile_key(session_name, account_id, role_name)
                default_alias = _default_alias(account_name, account_id, role_name)
                preference = preferences.get(key, {})
                alias = _alias_slug(
                    preference.get("alias", default_alias), f"alias {key}"
                )
                raw_regions = preference.get("regions", list(DEFAULT_CLIENT_REGIONS))
                if raw_regions == []:
                    raw_regions = list(DEFAULT_CLIENT_REGIONS)
                regions = _validated_regions(
                    raw_regions,
                    f"regiones {key}",
                    allow_empty=True,
                )
                suggested_regions = tuple(
                    region
                    for region in _validated_regions(
                        preference.get("suggestedRegions", []),
                        f"regiones sugeridas {key}",
                        allow_empty=True,
                    )
                    if region not in regions
                )
                assignments.append(
                    AwsSsoAssignment(
                        key=key,
                        account_id=account_id,
                        account_name=account_name,
                        role_name=role_name,
                        regions=regions,
                        suggested_regions=suggested_regions,
                        alias=alias,
                        default_alias=default_alias,
                        suggested_alias=_recommended_alias(
                            account_name, account_id, role_name
                        ),
                    )
                )
    except ConfigCtlError:
        raise
    except Exception as exc:
        raise ConfigCtlError(
            "aws-discovery-failed",
            "no se pudieron enumerar las cuentas y roles de AWS "
            f"({type(exc).__name__})",
        ) from exc

    if not accounts:
        raise ConfigCtlError(
            "aws-no-accounts", "AWS SSO no devolvió ninguna cuenta asignada"
        )
    if not assignments:
        raise ConfigCtlError(
            "aws-no-roles", "AWS SSO no devolvió ningún rol asignado"
        )
    return assignments, len(accounts)


def _render_managed_block(
    settings: AwsSsoSettings,
    profiles: list[AwsSsoProfile],
) -> str:
    lines = [MANAGED_BEGIN, "# Generado por Holodeck; usar el botón AWS para resincronizar."]
    if settings.manage_session:
        lines.extend(
            (
                f"[sso-session {settings.session_name}]",
                f"sso_start_url = {settings.start_url}",
                f"sso_region = {settings.sso_region}",
                "sso_registration_scopes = sso:account:access",
                "",
            )
        )
    for profile in profiles:
        lines.extend(
            (
                f"[profile {profile.name}]",
                f"sso_session = {settings.session_name}",
                f"sso_account_id = {profile.account_id}",
                f"sso_role_name = {profile.role_name}",
                f"region = {profile.region}",
                "output = json",
                "",
            )
        )
    lines.append(MANAGED_END)
    return "\n".join(lines) + "\n"


def _write_config(path: Path, base: str, block: str) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    content = base.rstrip()
    if content:
        content += "\n\n"
    content += block

    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        directory_descriptor = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def _load_access_token(environ: Mapping[str, str], settings: AwsSsoSettings) -> str:
    cache_key = hashlib.sha1(settings.session_name.encode("utf-8")).hexdigest()
    cache_path = _home(environ) / ".aws" / "sso" / "cache" / f"{cache_key}.json"
    try:
        payload = json.loads(cache_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ConfigCtlError(
            "missing-aws-sso-token",
            "AWS CLI no dejó un token SSO utilizable después del login",
        ) from exc
    access_token = payload.get("accessToken")
    if not isinstance(access_token, str) or not access_token:
        raise ConfigCtlError(
            "missing-aws-sso-token",
            "el cache de AWS SSO no contiene un access token utilizable",
        )
    return access_token


def _session_matches(
    parser: configparser.RawConfigParser,
    settings: AwsSsoSettings,
) -> bool:
    section = f"sso-session {settings.session_name}"
    if not parser.has_section(section):
        return False
    try:
        configured_url = _normalized_url(
            parser.get(section, "sso_start_url", fallback="")
        )
        configured_region = _validated_region(
            parser.get(section, "sso_region", fallback=""), "sso_region"
        )
    except ConfigCtlError:
        return False
    return (
        configured_url == settings.start_url
        and configured_region == settings.sso_region
    )


def _settings_from_catalog(
    environ: Mapping[str, str], catalog: Mapping[str, Any]
) -> tuple[AwsSsoSettings, str]:
    config_path = _aws_config_path(environ)
    original = _read_text(config_path)
    base, managed = _split_managed_block(original)
    parser = _parse_config(original)
    session_name = catalog["sessionName"]
    section = f"sso-session {session_name}"
    if not parser.has_section(section):
        raise ConfigCtlError(
            "missing-aws-session",
            "la sesión del catálogo ya no existe; ejecutá nuevamente la sincronización AWS",
        )
    start_url = _normalized_url(parser.get(section, "sso_start_url", fallback=""))
    sso_region = _validated_region(
        parser.get(section, "sso_region", fallback=""), "sso_region"
    )
    settings = AwsSsoSettings(
        start_url=start_url,
        sso_region=sso_region,
        session_name=_validated_session_name(session_name),
        manage_session=f"[{section}]" in managed,
    )
    return settings, base


def apply_aws_aliases(environ: Mapping[str, str]) -> dict[str, Any]:
    catalog = _load_catalog(environ)
    if catalog is None:
        raise ConfigCtlError(
            "missing-aws-alias-catalog",
            "todavía no hay perfiles descubiertos; ejecutá primero la sincronización AWS",
        )

    request_path = _alias_request_path(environ)
    request = _read_json(request_path, "la solicitud de alias AWS")
    if not isinstance(request, dict) or request.get("schemaVersion") != ALIAS_SCHEMA_VERSION:
        raise ConfigCtlError(
            "invalid-aws-aliases", "la solicitud de alias AWS falta o tiene una versión inválida"
        )
    requested = request.get("profiles")
    if not isinstance(requested, dict):
        raise ConfigCtlError(
            "invalid-aws-aliases", "la solicitud AWS no contiene preferencias de perfil válidas"
        )

    assignments_by_key = {
        assignment["key"]: assignment for assignment in catalog["assignments"]
    }
    requested_keys = set(requested)
    expected_keys = set(assignments_by_key)
    if requested_keys != expected_keys:
        raise ConfigCtlError(
            "invalid-aws-aliases",
            "la solicitud debe confirmar las regiones de todas las asignaciones AWS",
        )

    preferences = _load_preferences(environ, catalog)
    for key, raw_preference in requested.items():
        if not isinstance(key, str) or not PROFILE_KEY_RE.fullmatch(key):
            raise ConfigCtlError(
                "invalid-aws-aliases", "la solicitud contiene una clave de perfil inválida"
            )
        if (
            not isinstance(raw_preference, dict)
            or set(raw_preference) != {"alias", "regions"}
            or not isinstance(raw_preference.get("alias"), str)
        ):
            raise ConfigCtlError(
                "invalid-aws-aliases", "la solicitud contiene preferencias AWS inválidas"
            )
        item = assignments_by_key[key]
        raw_alias = raw_preference["alias"]
        alias = (
            item["defaultAlias"]
            if not raw_alias.strip()
            else _validated_alias(raw_alias, f"alias {key}")
        )
        regions = _validated_regions(
            raw_preference["regions"], f"regiones {key}", allow_empty=False
        )
        preferences[key] = {
            "alias": alias,
            "regions": list(regions),
            "suggestedRegions": [],
        }

    settings, base = _settings_from_catalog(environ, catalog)
    reserved_profiles = _reserved_profile_names(base)
    previous = _managed_profile_state(environ)
    assignments = _assignments_from_catalog(catalog, preferences)
    profiles = _expand_profiles(assignments, reserved_profiles)
    current = sorted((profile.name, profile.region) for profile in profiles)

    _write_config(
        _aws_config_path(environ), base, _render_managed_block(settings, profiles)
    )
    _write_private_json(
        _aliases_path(environ),
        _preferences_payload(assignments),
    )
    _write_private_json(
        _catalog_path(environ), _catalog_payload(settings, assignments)
    )
    request_path.unlink(missing_ok=True)
    return {
        "assignmentCount": len(assignments),
        "assignments": [
            _assignment_payload(assignment, profiles) for assignment in assignments
        ],
        "changed": current != previous,
        "command": "aws-aliases-apply",
        "ok": True,
        "pendingRegionCount": 0,
        "profileCount": len(profiles),
        "profiles": [_profile_payload(profile) for profile in profiles],
    }


def default_sso_client_factory(region: str) -> SsoClient:
    # Imported lazily so unit tests can exercise the complete workflow with a
    # fake client without needing boto3 on the developer's ambient PYTHONPATH.
    import boto3
    from botocore import UNSIGNED
    from botocore.config import Config

    return boto3.client(
        "sso",
        region_name=region,
        config=Config(signature_version=UNSIGNED),
    )


def sync_aws_sso(
    environ: Mapping[str, str],
    *,
    runner: Runner,
    input_fn: Input,
    stdout: TextIO,
    which: Which = shutil.which,
    client_factory: SsoClientFactory = default_sso_client_factory,
) -> dict[str, Any]:
    executable = _command_path("aws", environ, which)
    if executable is None:
        raise ConfigCtlError(
            "feature-unavailable",
            "la integración requiere `aws`; aplicá primero el perfil de Home Manager",
        )

    settings, base, _managed = _resolve_settings(
        environ, input_fn=input_fn, stdout=stdout
    )
    config_path = _aws_config_path(environ)
    reserved_profiles = _reserved_profile_names(base)

    full_parser = _parse_config(_read_text(config_path))
    if not _session_matches(full_parser, settings):
        _write_config(config_path, base, _render_managed_block(settings, []))

    argv = [
        executable,
        "sso",
        "login",
        "--sso-session",
        settings.session_name,
        "--no-cli-pager",
    ]
    stdout.write("Abriendo el login oficial de AWS IAM Identity Center…\n")
    try:
        completed = runner(
            argv,
            check=False,
            shell=False,
            text=True,
            env=dict(environ),
        )
    except OSError as exc:
        raise ConfigCtlError(
            "exec-failed", f"no se pudo iniciar AWS CLI: {exc}", exit_code=1
        ) from exc

    if completed.returncode != 0:
        return {
            "action": "aws-sync",
            "argv": argv,
            "command": "action",
            "exitCode": completed.returncode,
            "ok": False,
        }

    access_token = _load_access_token(environ, settings)
    client = client_factory(settings.sso_region)
    previous_catalog = _load_catalog(environ)
    preferences = _load_preferences(environ, previous_catalog)
    assignments, account_count = _discover_assignments(
        client,
        access_token,
        settings.session_name,
        preferences,
    )
    profiles = _expand_profiles(assignments, reserved_profiles)
    pending_region_count = sum(
        1 for assignment in assignments if not assignment.regions
    )
    _write_config(config_path, base, _render_managed_block(settings, profiles))
    _write_private_json(
        _aliases_path(environ), _preferences_payload(assignments)
    )
    _write_private_json(
        _catalog_path(environ), _catalog_payload(settings, assignments)
    )
    stdout.write(
        f"AWS SSO sincronizado: {len(assignments)} asignaciones para "
        f"{account_count} cuentas; {len(profiles)} perfiles regionales generados.\n"
    )
    if pending_region_count:
        stdout.write(
            f"Región pendiente en {pending_region_count} asignaciones; "
            "completalas en Holodeck Control para generar sus perfiles.\n"
        )
    return {
        "accountCount": account_count,
        "action": "aws-sync",
        "assignmentCount": len(assignments),
        "assignments": [
            _assignment_payload(assignment, profiles) for assignment in assignments
        ],
        "argv": argv,
        "command": "action",
        "exitCode": 0,
        "ok": True,
        "pendingRegionCount": pending_region_count,
        "profileCount": len(profiles),
        "profiles": [_profile_payload(profile) for profile in profiles],
    }
