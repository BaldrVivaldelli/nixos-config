#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'MSG'
Uso:
  ./install.sh
  ./install.sh home-manager
  ./install.sh nixos
  ./install.sh nixos home-manager
  ./install.sh nixos wsl
  ./install.sh BACKEND [argumentos del backend]

Sin argumentos abre un selector interactivo.

Targets incluidos:
  home-manager  Configura el usuario sobre un NixOS existente.
  nixos wsl     Prepara el host NixOS-WSL declarado por la flake.
  otro          Una app de flake o ejecutable holodeck-system-BACKEND.
MSG
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

choose_backend() {
  cat >&2 <<'MSG'
Seleccioná qué querés instalar:
  1) Home Manager sobre un NixOS existente
  2) NixOS-WSL
  3) Otro backend instalado
MSG
  printf "Opción [1-3]: " >&2
  IFS= read -r selection
  case "$selection" in
    1) printf "home-manager" ;;
    2) printf "nixos" ;;
    3)
      printf "ID del backend (por ejemplo ubuntu o macos): " >&2
      IFS= read -r custom_backend
      printf "%s" "$custom_backend"
      ;;
    *) fail "opción de sistema inválida" ;;
  esac
}

install_home_manager() {
  echo "==> Verificando que Home Manager no administre el sistema..." >&2
  bash "$repo_dir/verify-user-only.sh"

  echo "==> Construyendo el perfil de Home Manager..." >&2
  bash "$repo_dir/apply-home.sh" build

  echo "==> Instalando y activando el perfil de Home Manager..." >&2
  bash "$repo_dir/apply-home.sh" switch
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
  home|home-manager|existing-nixos)
    if [[ $# -ne 0 ]]; then
      fail "home-manager no acepta argumentos adicionales"
    fi
    install_home_manager
    ;;
  nix-os|nixos)
    target="wsl"
    if [[ $# -gt 0 && "$1" != -* ]]; then
      target="$1"
      shift
    fi

    case "$target" in
      home|home-manager|existing-nixos)
        if [[ $# -ne 0 ]]; then
          fail "home-manager no acepta argumentos adicionales"
        fi
        install_home_manager
        exit 0
        ;;
      wsl) ;;
      *) fail "target NixOS desconocido: $target (usá home-manager o wsl)" ;;
    esac

    if ! command -v nix >/dev/null 2>&1; then
      fail "el backend NixOS requiere el comando nix"
    fi

    cd "$repo_dir"
    nix_command=(
      nix
      --extra-experimental-features "nix-command flakes"
      run .#holodeck-system-nixos --
      install
      --target wsl
      --repo "$repo_dir"
      "$@"
    )
    exec "${nix_command[@]}"
    ;;
  *)
    if [[ ! "$backend" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
      fail "ID de backend inválido: $backend"
    fi

    backend_command="holodeck-system-$backend"
    if command -v "$backend_command" >/dev/null 2>&1; then
      exec "$backend_command" install --repo "$repo_dir" "$@"
    fi

    if command -v nix >/dev/null 2>&1; then
      cd "$repo_dir"
      nix_command=(
        nix
        --extra-experimental-features "nix-command flakes"
        run ".#$backend_command" --
        install
        --repo "$repo_dir"
        "$@"
      )
      exec "${nix_command[@]}"
    fi

    fail "backend no instalado: $backend_command"
    ;;
esac
