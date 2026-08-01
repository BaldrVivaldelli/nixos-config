#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_dir"

for forbidden_path in \
  install-desktop.sh \
  modules/hosts \
  modules/nixos \
  holodeck/backends/nixos; do
  if [[ -e "$forbidden_path" ]]; then
    echo "Error: se encontro una ruta de administracion del sistema: $forbidden_path" >&2
    exit 1
  fi
done

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
  'holodeck-system-nixos'
)

mapfile -d '' source_files < <(
  find . -type f \
    \( -name '*.nix' -o -name '*.sh' \) \
    ! -name 'verify-user-only.sh' \
    -print0
)

for pattern in "${patterns[@]}"; do
  if grep -En -- "$pattern" "${source_files[@]}"; then
    echo "Error: se encontro una referencia de sistema prohibida: $pattern" >&2
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
  echo "Error: Holodeck no esta usando el launcher silencioso para GitHub CLI." >&2
  exit 1
fi

if ! grep -Fq -- '>/dev/null 2>&1 &' packages/holodeck/default.nix; then
  echo "Error: el launcher del navegador no silencia stdout/stderr." >&2
  exit 1
fi

echo "OK: el repositorio solo contiene configuracion de usuario de Home Manager."
