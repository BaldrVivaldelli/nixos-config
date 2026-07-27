#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'MSG'
Uso:
  ./install.sh
  ./install.sh nixos desktop
  ./install.sh nixos wsl
  ./install.sh BACKEND [argumentos del backend]

Sin argumentos abre un selector interactivo.
Desktop detecta el disco automaticamente. Para reinstalar el sistema activo:
  ./install.sh nixos desktop --disk /dev/disk/by-id/ID \
    --allow-running-system-disk

Backends:
  nixos   Incluido en este repo; targets: desktop y wsl.
  otro    Una app de flake o ejecutable llamado holodeck-system-BACKEND.
MSG
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

choose_backend() {
  cat >&2 <<'MSG'
Selecciona el sistema que queres instalar:
  1) NixOS
  2) Otro backend instalado
MSG
  printf "Opcion [1-2]: " >&2
  IFS= read -r selection
  case "$selection" in
    1) printf "nixos" ;;
    2)
      printf "ID del backend (por ejemplo ubuntu o macos): " >&2
      IFS= read -r custom_backend
      printf "%s" "$custom_backend"
      ;;
    *) fail "opcion de sistema invalida" ;;
  esac
}

choose_nixos_target() {
  cat >&2 <<'MSG'
Selecciona el target NixOS:
  1) Desktop fisico
  2) WSL
MSG
  printf "Opcion [1-2]: " >&2
  IFS= read -r selection
  case "$selection" in
    1) printf "desktop" ;;
    2) printf "wsl" ;;
    *) fail "target NixOS invalido" ;;
  esac
}

case "${1:-}" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

if [[ $# -gt 0 ]]; then
  backend="$1"
  shift
else
  backend="$(choose_backend)"
fi

case "$backend" in
  nix-os|nixos)
    if [[ $# -gt 0 && "$1" != -* ]]; then
      target="$1"
      shift
    else
      target="$(choose_nixos_target)"
    fi

    case "$target" in
      desktop|wsl) ;;
      *) fail "target NixOS desconocido: $target (usa desktop o wsl)" ;;
    esac

    if [[ "$target" == "desktop" && $# -gt 0 && "$1" != -* ]]; then
      target_disk="$1"
      shift
      set -- --disk "$target_disk" "$@"
    fi

    command -v nix >/dev/null 2>&1 \
      || fail "el backend NixOS requiere el comando nix"

    cd "$repo_dir"
    exec nix \
      --extra-experimental-features "nix-command flakes" \
      run .#holodeck-system-nixos -- \
      install \
      --target "$target" \
      --repo "$repo_dir" \
      "$@"
    ;;
  *)
    [[ "$backend" =~ ^[a-z0-9][a-z0-9-]*$ ]] \
      || fail "ID de backend invalido: $backend"

    backend_command="holodeck-system-$backend"
    if command -v "$backend_command" >/dev/null 2>&1; then
      exec "$backend_command" install --repo "$repo_dir" "$@"
    fi

    if command -v nix >/dev/null 2>&1; then
      cd "$repo_dir"
      exec nix \
        --extra-experimental-features "nix-command flakes" \
        run ".#$backend_command" -- \
        install \
        --repo "$repo_dir" \
        "$@"
    fi

    fail "backend no instalado: $backend_command"
    ;;
esac
