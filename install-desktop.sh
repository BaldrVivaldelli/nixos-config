#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_dir"

if ! command -v nix >/dev/null 2>&1; then
  echo "Error: no se encontro el comando nix." >&2
  exit 1
fi

# Conserva la interfaz historica:
#   ./install-desktop.sh /dev/disk/by-id/ID
# y tambien acepta la forma explicita:
#   ./install-desktop.sh --disk /dev/disk/by-id/ID
if [[ $# -gt 0 && "$1" != -* ]]; then
  target_disk="$1"
  shift
  set -- --disk "$target_disk" "$@"
fi

exec nix \
  --extra-experimental-features "nix-command flakes" \
  run .#holodeck -- \
  system install \
  --host desktop \
  --repo "$repo_dir" \
  "$@"
