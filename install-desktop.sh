#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -ne 0 ]]; then
  echo "Uso: ./install-desktop.sh" >&2
  exit 1
fi

command -v nix >/dev/null 2>&1 \
  || {
    echo "Error: install-desktop.sh requiere el comando nix" >&2
    exit 1
  }

cd "$repo_dir"
exec nix \
  --extra-experimental-features "nix-command flakes" \
  run .#holodeck-system-nixos -- \
  install \
  --target desktop \
  --repo "$repo_dir"
