#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_dir"

forbidden_paths=(
  install-desktop.sh
  modules/hosts/desktop
  modules/hosts/reinstaller
)

for forbidden_path in "${forbidden_paths[@]}"; do
  if [[ -e "$forbidden_path" ]]; then
    echo "Error: reapareció una ruta del desktop físico: $forbidden_path" >&2
    exit 1
  fi
done

patterns=(
  'nixosConfigurations[.]desktop'
  'desktop-disko'
  'reinstaller-kexec'
  'allow-running-system-disk'
  '/dev/disk/by-'
  '/dev/mapper/'
  'cryptroot'
  '(^|[^[:alnum:]_])disko([^[:alnum:]_]|$)'
  '(^|[[:space:]])fileSystems([.]|[[:space:]])'
  '(^|[[:space:]])swapDevices([.]|[[:space:]])'
)

search_roots=(
  flake.nix
  install.sh
  holodeck/backends/nixos
  modules/hosts
  modules/nixos
)

mapfile -d '' source_files < <(
  find "${search_roots[@]}" -type f \( -name '*.nix' -o -name '*.sh' -o -name '*.py' \) -print0
)

for pattern in "${patterns[@]}"; do
  if grep -Ein -- "$pattern" "${source_files[@]}"; then
    echo "Error: reapareció lógica de instalación o almacenamiento del desktop: $pattern" >&2
    exit 1
  fi
done

echo "OK: WSL y los backends no contienen lógica del desktop físico ni de discos."
