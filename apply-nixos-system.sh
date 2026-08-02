#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
mode="${1:-switch}"
system_root="${NIXOS_CONFIG_SYSTEM_ROOT:-/}"
configuration_file="${NIXOS_EXISTING_CONFIGURATION:-${system_root%/}/etc/nixos/configuration.nix}"
readonly required_nix_features="nix-command flakes"

usage() {
  cat <<'MSG'
Uso:
  ./apply-nixos-system.sh build   # construye el sistema sin activarlo
  ./apply-nixos-system.sh switch  # construye y activa el sistema

Reutiliza /etc/nixos/configuration.nix y su hardware-configuration.nix, y les
superpone el perfil seguro modules/nixos/profiles/niri-desktop. No copia ni
declara discos, UUID, filesystems, particiones o bootloader dentro del repo.
MSG
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

is_wsl_environment() {
  local kernel_release=""
  if [[ -r /proc/sys/kernel/osrelease ]]; then
    IFS= read -r kernel_release < /proc/sys/kernel/osrelease || true
  fi
  [[ "${kernel_release,,}" == *microsoft* || -n "${WSL_INTEROP:-}" || -n "${WSL_DISTRO_NAME:-}" ]]
}

case "$mode" in
  build|switch) ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *) fail "modo desconocido: $mode (usá build o switch)" ;;
esac

[[ -e "${system_root%/}/etc/NIXOS" ]] || fail "este flujo requiere un NixOS existente"
if is_wsl_environment; then
  fail "este flujo es para NixOS físico; en WSL usá ./install.sh nixos wsl"
fi
[[ -r "$configuration_file" ]] || fail "no se puede leer $configuration_file"

for command_name in nix nixos-rebuild sudo; do
  command -v "$command_name" >/dev/null 2>&1 || fail "no se encontró el comando $command_name"
done

bash "$repo_dir/verify-no-desktop.sh"

work_dir="$(mktemp -d)"
cleanup() {
  if [[ -L "$work_dir/result" ]]; then
    rm -f -- "$work_dir/result"
  fi
  rmdir -- "$work_dir" 2>/dev/null || true
}
trap cleanup EXIT

echo "==> ${mode^} del NixOS existente con el perfil Niri del repositorio..." >&2
cd "$work_dir"
sudo env \
  "NIXOS_EXISTING_CONFIGURATION=$configuration_file" \
  nixos-rebuild "$mode" \
  --impure \
  --flake "path:$repo_dir#existing" \
  --option experimental-features "$required_nix_features"
