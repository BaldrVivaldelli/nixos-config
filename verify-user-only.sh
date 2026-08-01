#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_dir"

patterns=(
  'nixosConfigurations'
  'nixosSystem'
  'nixos-rebuild'
  'hardware-configuration'
  '/dev/disk/by-'
  '/dev/mapper/'
  'boot[.]loader'
  'boot[.]initrd'
  'fileSystems'
  'swapDevices'
  'system[.]build'
)

search_roots=(
  apply-home.sh
  home
  modules/home/features
  modules/home/profiles
  packages/holodeck
)

mapfile -d '' source_files < <(
  find "${search_roots[@]}" -type f \( -name '*.nix' -o -name '*.sh' \) -print0
)

for pattern in "${patterns[@]}"; do
  if grep -En -- "$pattern" "${source_files[@]}"; then
    echo "Error: la configuración Home Manager contiene una referencia de sistema: $pattern" >&2
    exit 1
  fi
done

if ! grep -Fq -- '--extra-experimental-features "$required_nix_features"' apply-home.sh; then
  echo "Error: apply-home.sh no pasa las features experimentales al comando nix inicial." >&2
  exit 1
fi

if ! grep -Fq -- 'experimental-features = ${required_nix_features}' apply-home.sh; then
  echo "Error: apply-home.sh no propaga las features a los procesos hijos de Home Manager." >&2
  exit 1
fi

if ! grep -Fq -- 'export GH_BROWSER=${quietBrowser}/bin/holodeck-open-browser' packages/holodeck/default.nix; then
  echo "Error: Holodeck no está usando el launcher silencioso para GitHub CLI." >&2
  exit 1
fi

if ! grep -Fq -- '>/dev/null 2>&1 &' packages/holodeck/default.nix; then
  echo "Error: el launcher del navegador no silencia stdout/stderr." >&2
  exit 1
fi

identity_patterns=(
  'homeConfigurations[.][[:alnum:]_-]+'
  'home-manager[.]users[.][[:alnum:]_-]+'
  'users[.]users[.][[:alnum:]_-]+'
  '"/home/[[:alnum:]_]'
  'home/[[:alnum:]_-]+/default[.]nix'
)

identity_roots=(
  flake.nix
  apply-home.sh
  home
  lib
  modules/home
  modules/hosts/wsl
  holodeck/backends/nixos
)

mapfile -d '' identity_files < <(
  find "${identity_roots[@]}" -type f \( -name '*.nix' -o -name '*.sh' -o -name '*.py' \) -print0
)

for pattern in "${identity_patterns[@]}"; do
  if grep -En -- "$pattern" "${identity_files[@]}"; then
    echo "Error: una identidad de usuario quedó acoplada fuera de inventory.nix: $pattern" >&2
    exit 1
  fi
done

if ! grep -Fq -- '--flake "path:$repo_dir#default"' apply-home.sh; then
  echo "Error: apply-home.sh no usa el alias portable homeConfigurations.default." >&2
  exit 1
fi

echo "OK: Home Manager no administra el sistema y deriva la identidad desde inventory.nix."
