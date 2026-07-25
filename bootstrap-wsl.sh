#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
expected_dir="/home/avivaldelli/projects/personal/nixos-config"

cd "$repo_dir"

if [[ ! -f flake.nix || ! -d modules/hosts/wsl ]]; then
  echo "Error: ejecuta este script desde la raiz del repo completo." >&2
  exit 1
fi

if ! command -v nix >/dev/null 2>&1; then
  echo "Error: no se encontro el comando nix." >&2
  exit 1
fi

if ! command -v nixos-rebuild >/dev/null 2>&1; then
  echo "Error: este script debe ejecutarse dentro de NixOS-WSL." >&2
  exit 1
fi

if [[ "$repo_dir" != "$expected_dir" ]]; then
  cat <<MSG
Aviso: el repo esta en:
  $repo_dir

Los aliases nixswitch/nixbuild esperan:
  $expected_dir

La primera instalacion puede continuar, pero conviene mover el repo a esa ruta
antes de usar los aliases del shell.
MSG
fi

if command -v git >/dev/null 2>&1 \
  && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  untracked_wsl="$(git ls-files --others --exclude-standard -- \
    flake.nix \
    modules/hosts/wsl \
    modules/home/features/shell/default.nix \
    bootstrap-wsl.sh \
    docs/wsl.md \
    FIRST_RUN_WSL.md || true)"
  if [[ -n "$untracked_wsl" ]]; then
    cat >&2 <<MSG
Error: hay archivos WSL sin seguimiento dentro del repositorio Git:
$untracked_wsl

Agregalos antes de evaluar la flake, por ejemplo:
  git add flake.nix flake.lock modules/hosts/wsl \
    modules/home/features/shell/default.nix bootstrap-wsl.sh \
    FIRST_RUN_WSL.md docs/wsl.md README.md CHANGELOG.md docs/index.md
MSG
    exit 1
  fi
fi

echo "==> Validando la flake fijada en flake.lock"
echo "    Para actualizar NixOS-WSL mas adelante: nix flake update nixos-wsl"

echo "==> Ejecutando nix flake check"
nix --extra-experimental-features "nix-command flakes" \
  flake check

echo "==> Preparando la primera generacion de #wsl"
echo "    Se usa 'boot' porque cambia el usuario predeterminado de nixos a avivaldelli."
sudo nixos-rebuild boot \
  --flake .#wsl \
  --option experimental-features "nix-command flakes"

cat <<'MSG'

La generacion fue preparada. Ahora sali de NixOS-WSL:

  exit

Luego, en PowerShell de Windows, ejecuta estos comandos. Reemplaza NixOS si
'wsl -l -v' muestra otro nombre para la distribucion:

  wsl -l -v
  wsl --terminate NixOS
  wsl -d NixOS --user root exit
  wsl --terminate NixOS
  wsl -d NixOS

La nueva sesion deberia abrir como avivaldelli@nixos-wsl.
A partir de ahi, las siguientes actualizaciones se aplican con:

  cd ~/projects/personal/nixos-config
  nixswitch

El repo ya incluye NixOS-WSL fijado en flake.lock. Para actualizar solamente
ese input en otro momento, ejecuta:

  nix flake update nixos-wsl
MSG
