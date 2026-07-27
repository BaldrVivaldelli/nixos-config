#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'MSG'
Uso:
  ./install-desktop.sh
  ./install-desktop.sh --disk /dev/disk/by-id/ID
  ./install-desktop.sh --disk /dev/disk/by-id/ID --allow-running-system-disk

Sin argumentos detecta solamente discos seguros. El ultimo modo es destructivo,
requiere confirmaciones adicionales y arranca un instalador efimero con kexec.
MSG
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

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
  --repo "$repo_dir" \
  "$@"
