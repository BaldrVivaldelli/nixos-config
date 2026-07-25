#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_dir"

if ! command -v nix >/dev/null 2>&1; then
  echo "Error: no se encontro el comando nix." >&2
  exit 1
fi

exec nix \
  --extra-experimental-features "nix-command flakes" \
  run .#holodeck -- \
  system install \
  --host wsl \
  --repo "$repo_dir" \
  "$@"
