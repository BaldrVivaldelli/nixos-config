#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
mode="${1:-switch}"
system_root="${NIXOS_CONFIG_SYSTEM_ROOT:-/}"
configuration_file="${NIXOS_EXISTING_CONFIGURATION:-${system_root%/}/etc/nixos/configuration.nix}"
readonly required_nix_features="nix-command flakes"
source_dir="${NIXOS_CONFIG_FLAKE_SOURCE:-}"
owns_source=0

usage() {
  cat <<'MSG'
Uso:
  ./apply-nixos-system.sh build   # construye el sistema sin activarlo
  ./apply-nixos-system.sh switch  # construye y activa el sistema
  ./apply-nixos-system.sh validate # valida el host sin construir

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
  build|switch|validate) ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *) fail "modo desconocido: $mode (usá build, switch o validate)" ;;
esac

[[ -e "${system_root%/}/etc/NIXOS" ]] || fail "este flujo requiere un NixOS existente"
if is_wsl_environment; then
  fail "este flujo es para NixOS físico; en WSL usá ./install.sh nixos wsl"
fi
[[ -r "$configuration_file" ]] || fail "no se puede leer $configuration_file"

bash "$repo_dir/verify-no-desktop.sh"

if [[ "$mode" == "validate" ]]; then
  exit 0
fi

for command_name in nix nixos-rebuild sudo; do
  command -v "$command_name" >/dev/null 2>&1 || fail "no se encontró el comando $command_name"
done

if [[ -z "$source_dir" ]]; then
  source_dir="$(bash "$repo_dir/prepare-flake-source.sh")"
  owns_source=1
else
  case "$source_dir" in
    /nix/store/*|"${TMPDIR:-/tmp}"/nixos-config-source.*) ;;
    *) fail "NIXOS_CONFIG_FLAKE_SOURCE no es un snapshot administrado" ;;
  esac
fi
[[ -f "$source_dir/flake.nix" ]] || fail "el snapshot de la flake no contiene flake.nix: $source_dir"

work_dir="$(mktemp -d)"
cleanup() {
  if [[ -L "$work_dir/result" ]]; then
    rm -f -- "$work_dir/result"
  fi
  rmdir -- "$work_dir" 2>/dev/null || true
  if [[ "$owns_source" -eq 1 ]]; then
    case "$source_dir" in
      "${TMPDIR:-/tmp}"/nixos-config-source.*) rm -rf -- "$source_dir" ;;
      *) echo "Error: se rechazó limpiar una ruta temporal inesperada: $source_dir" >&2 ;;
    esac
  fi
}
trap cleanup EXIT

echo "==> ${mode^} del NixOS existente con el perfil Niri del repositorio..." >&2
cd "$work_dir"
rebuild_args=(
  nixos-rebuild "$mode"
  --impure
  --flake "path:$source_dir#existing"
  --option experimental-features "$required_nix_features"
)

if [[ "$mode" == "switch" ]]; then
  sudo env "NIXOS_EXISTING_CONFIGURATION=$configuration_file" "${rebuild_args[@]}"
else
  env "NIXOS_EXISTING_CONFIGURATION=$configuration_file" "${rebuild_args[@]}"
fi
