#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mode="${1:-switch}"
readonly required_nix_features="nix-command flakes"
source_dir="${NIXOS_CONFIG_FLAKE_SOURCE:-}"
owns_source=0

note() {
  if [[ -t 2 && -z "${NO_COLOR+x}" && "${TERM:-}" != "dumb" ]]; then
    printf '\033[1;33mNota: %s\033[0m\n' "$*" >&2
  else
    printf 'Nota: %s\n' "$*" >&2
  fi
}

usage() {
  cat <<'MSG'
Uso:
  ./apply-home.sh          # instala y activa la configuracion personal
  ./apply-home.sh switch   # igual que el comando anterior
  ./apply-home.sh build    # construye sin instalar ni activar

Este flujo usa Home Manager standalone. No particiona discos, no modifica el
bootloader, el kernel, los filesystems, los usuarios del sistema ni servicios
de NixOS. La identidad activa es `defaultHomeUser` en el inventario efectivo.
MSG
}

case "$mode" in
  switch|build) ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    echo "Error: modo desconocido: $mode (usa switch o build)" >&2
    exit 2
    ;;
esac

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Error: apply-home.sh debe ejecutarse como el usuario normal, sin sudo." >&2
  exit 1
fi

command -v nix >/dev/null 2>&1 || {
  echo "Error: no se encontro el comando nix." >&2
  exit 1
}

if [[ -z "$source_dir" ]]; then
  source_dir="$(bash "$repo_dir/prepare-flake-source.sh")"
  owns_source=1
else
  case "$source_dir" in
    /nix/store/*|"${TMPDIR:-/tmp}"/nixos-config-source.*) ;;
    *)
      echo "Error: NIXOS_CONFIG_FLAKE_SOURCE no es un snapshot administrado." >&2
      exit 1
      ;;
  esac
fi
[[ -f "$source_dir/flake.nix" ]] || {
  echo "Error: el snapshot de la flake no contiene flake.nix: $source_dir" >&2
  exit 1
}

cleanup() {
  if [[ "$owns_source" -eq 1 ]]; then
    case "$source_dir" in
      "${TMPDIR:-/tmp}"/nixos-config-source.*) rm -rf -- "$source_dir" ;;
      *) echo "Error: se rechazó limpiar una ruta temporal inesperada: $source_dir" >&2 ;;
    esac
  fi
}
trap cleanup EXIT

# Home Manager ejecuta otros procesos `nix` internamente. NIX_CONFIG hace que
# esos procesos hijos tambien reciban las features, sin tocar /etc/nix/nix.conf.
# Se usa `experimental-features` por compatibilidad con versiones antiguas de Nix.
if [[ -n "${NIX_CONFIG:-}" ]]; then
  export NIX_CONFIG="${NIX_CONFIG}"$'\n'"experimental-features = ${required_nix_features}"
else
  export NIX_CONFIG="experimental-features = ${required_nix_features}"
fi

if [[ "$mode" == "build" ]]; then
  echo "Construyendo la configuracion sin activarla..." >&2
  note "build no instala los programas. Luego ejecuta: ./apply-home.sh switch"
else
  echo "Instalando y activando los programas del usuario..." >&2
  echo "Los archivos previos en conflicto se conservaran con extension .hm-bak." >&2
fi

cd "$repo_dir"

# El flag explicito habilita las features para este primer `nix run` incluso si
# la configuracion global de NixOS las tiene deshabilitadas.
home_manager_args=("$mode")
if [[ "$mode" == "switch" ]]; then
  home_manager_args+=( -b hm-bak )
fi
home_manager_args+=(--flake "path:$source_dir#default")

nix \
  --extra-experimental-features "$required_nix_features" \
  run "path:$source_dir#home-manager" -- \
  "${home_manager_args[@]}"
