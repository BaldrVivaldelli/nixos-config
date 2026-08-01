#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mode="${1:-switch}"
readonly required_nix_features="nix-command flakes"

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
  echo "Nota: build no instala los programas. Luego ejecuta: ./apply-home.sh switch" >&2
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
home_manager_args+=(--flake "path:$repo_dir#default")

exec nix \
  --extra-experimental-features "$required_nix_features" \
  run "path:$repo_dir#home-manager" -- \
  "${home_manager_args[@]}"
