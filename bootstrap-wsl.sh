#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "Aviso: bootstrap-wsl.sh es un alias compatible; usa install-wsl.sh."
exec "$repo_dir/install-wsl.sh" "$@"
