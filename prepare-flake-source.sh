#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly source_prefix="${TMPDIR:-/tmp}/nixos-config-source."
mode="${1:-print}"

fail() {
  echo "Error: $*" >&2
  exit 1
}

case "$mode" in
  print) [[ $# -eq 0 ]] || fail "el modo print no acepta argumentos" ;;
  --check) shift ;;
  -h|--help|help)
    cat <<'MSG'
Uso:
  ./prepare-flake-source.sh
  ./prepare-flake-source.sh --check [argumentos de nix flake check]

Sin argumentos imprime la ruta de un snapshot temporal y deja su limpieza al
caller. --check crea el snapshot, ejecuta la validación y lo elimina al salir.
MSG
    exit 0
    ;;
  *) fail "modo desconocido: $mode (usá --check o --help)" ;;
esac

command -v git >/dev/null 2>&1 || fail "no se encontró el comando git"
command -v cp >/dev/null 2>&1 || fail "no se encontró el comando cp"

git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "$repo_dir no es un working tree de Git"

unexpected_untracked=()
while IFS= read -r -d '' relative_path; do
  # Este script puede estar todavía sin stagear mientras se aplica el cambio.
  # Una vez agregado al índice pasa por el camino normal de archivos versionados.
  if [[ "$relative_path" != "prepare-flake-source.sh" ]]; then
    unexpected_untracked+=("$relative_path")
  fi
done < <(git -C "$repo_dir" ls-files --others --exclude-standard -z)

if (( ${#unexpected_untracked[@]} > 0 )); then
  printf 'Error: hay archivos fuente sin versionar; el snapshot seguro no los incluiría:\n' >&2
  printf '  %s\n' "${unexpected_untracked[@]}" >&2
  fail "agregalos al índice o elimínalos antes de evaluar la flake"
fi

source_dir="$(mktemp -d "${source_prefix}XXXXXX")"
[[ "$source_dir" == "$source_prefix"* ]] || fail "mktemp devolvió una ruta inesperada"

copy_file() {
  local relative_path=$1
  local source_path="$repo_dir/$relative_path"
  local target_path="$source_dir/$relative_path"

  if [[ ! -e "$source_path" && ! -L "$source_path" ]]; then
    return
  fi
  [[ ! -d "$source_path" ]] \
    || fail "los gitlinks/submódulos no están soportados por el snapshot: $relative_path"

  mkdir -p -- "$(dirname -- "$target_path")"
  cp -a -- "$source_path" "$target_path"
}

while IFS= read -r -d '' relative_path; do
  [[ "$relative_path" != .git && "$relative_path" != .git/* ]] \
    || fail "Git devolvió una ruta interna inesperada: $relative_path"
  copy_file "$relative_path"
done < <(git -C "$repo_dir" ls-files --cached -z)

# Bootstrap de esta migración: mientras el helper todavía no esté en el índice,
# se incluye por nombre exacto. Una vez stageado ya fue copiado por el loop.
if ! git -C "$repo_dir" ls-files --error-unmatch -- prepare-flake-source.sh >/dev/null 2>&1; then
  copy_file prepare-flake-source.sh
fi

# Son los únicos datos locales que forman parte deliberada de la evaluación.
# Se rechazan symlinks para que el allowlist no pueda apuntar fuera del repo.
for relative_path in inventory.local.nix holodeck.local.json; do
  local_path="$repo_dir/$relative_path"
  if [[ "$relative_path" == "inventory.local.nix" && -n "${NIXOS_CONFIG_INVENTORY_PATH:-}" ]]; then
    local_path="$NIXOS_CONFIG_INVENTORY_PATH"
  fi
  if [[ -e "$local_path" ]]; then
    [[ -f "$local_path" && ! -L "$local_path" ]] \
      || fail "$relative_path debe ser un archivo regular, no un symlink"
    mkdir -p -- "$(dirname -- "$source_dir/$relative_path")"
    cp -a -- "$local_path" "$source_dir/$relative_path"
  fi
done

if [[ "$mode" == "--check" ]]; then
  cleanup() {
    case "$source_dir" in
      "$source_prefix"*) rm -rf -- "$source_dir" ;;
      *) fail "se rechazó limpiar una ruta temporal inesperada: $source_dir" ;;
    esac
  }
  trap cleanup EXIT
  exec_status=0
  nix --extra-experimental-features "nix-command flakes" \
    flake check "path:$source_dir" "$@" || exec_status=$?
  exit "$exec_status"
fi

printf '%s\n' "$source_dir"
