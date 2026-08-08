#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'MSG'
Uso:
  ./install.sh
  ./install.sh configure [--print|--yes|--force]
  ./install.sh existing-nixos
  ./install.sh home-manager
  ./install.sh recover MANIFEST
  ./install.sh regenerate
  ./install.sh nixos
  ./install.sh nixos existing
  ./install.sh nixos home-manager
  ./install.sh nixos wsl
  ./install.sh BACKEND [argumentos del backend]

Sin argumentos abre un selector interactivo.

Targets incluidos:
  configure      Detecta esta máquina y crea inventory.local.nix.
  existing-nixos Configura Niri en el sistema y aplica Home Manager.
  home-manager   Aplica solamente la configuración del usuario.
  recover        Reactiva las generaciones previas de un manifiesto.
  regenerate     Regenera Home Manager y recarga Holodeck Control.
  nixos wsl      Prepara el host NixOS-WSL declarado por la flake.
  otro           Una app de flake o ejecutable holodeck-system-BACKEND.
MSG
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

choose_backend() {
  cat >&2 <<'MSG'
Seleccioná qué querés instalar:
  1) NixOS físico existente: Niri + Home Manager
  2) NixOS-WSL
  3) Otro backend instalado
  4) Sólo detectar y configurar esta máquina
MSG
  printf "Opción [1-4]: " >&2
  IFS= read -r selection
  case "$selection" in
    1) printf "existing-nixos" ;;
    2) printf "nixos" ;;
    3)
      printf "ID del backend (por ejemplo ubuntu o macos): " >&2
      IFS= read -r custom_backend
      printf "%s" "$custom_backend"
      ;;
    4) printf "configure" ;;
    *) fail "opción de sistema inválida" ;;
  esac
}

configure_inventory_if_needed() {
  local inventory_path="${NIXOS_CONFIG_INVENTORY_PATH:-$repo_dir/inventory.local.nix}"
  if [[ -f "$inventory_path" && ! -L "$inventory_path" ]]; then
    return
  fi

  if [[ -e "$inventory_path" ]]; then
    fail "el inventario debe ser un archivo regular, no un symlink: $inventory_path"
  fi

  if [[ -t 0 ]]; then
    echo "==> No hay un inventario para esta máquina; voy a detectar sus características." >&2
    if [[ -n "${NIXOS_CONFIG_INVENTORY_PATH:-}" ]]; then
      bash "$repo_dir/configure-inventory.sh" --output "$inventory_path"
    else
      bash "$repo_dir/configure-inventory.sh"
    fi
  else
    fail "falta inventory.local.nix; ejecutá ./install.sh configure --yes antes de aplicar cambios"
  fi
}

prepare_flake_source() {
  if [[ -n "${NIXOS_CONFIG_FLAKE_SOURCE:-}" ]]; then
    case "$NIXOS_CONFIG_FLAKE_SOURCE" in
      /nix/store/*|"${TMPDIR:-/tmp}"/nixos-config-source.*) ;;
      *) fail "NIXOS_CONFIG_FLAKE_SOURCE no es un snapshot administrado" ;;
    esac
    [[ -f "$NIXOS_CONFIG_FLAKE_SOURCE/flake.nix" ]] \
      || fail "NIXOS_CONFIG_FLAKE_SOURCE no contiene flake.nix"
    printf '%s\n' "$NIXOS_CONFIG_FLAKE_SOURCE"
  else
    bash "$repo_dir/prepare-flake-source.sh"
  fi
}

cleanup_flake_source() {
  local source_dir=$1
  if [[ -n "${NIXOS_CONFIG_FLAKE_SOURCE:-}" && "$source_dir" == "$NIXOS_CONFIG_FLAKE_SOURCE" ]]; then
    return
  fi
  case "$source_dir" in
    "${TMPDIR:-/tmp}"/nixos-config-source.*) rm -rf -- "$source_dir" ;;
    *) echo "Error: se rechazó limpiar una ruta temporal inesperada: $source_dir" >&2 ;;
  esac
}

readonly required_nix_features="nix-command flakes"
readonly store_root="${NIXOS_CONFIG_STORE_ROOT:-/nix/store}"

home_manager_profile() {
  if [[ -n "${NIXOS_CONFIG_HM_PROFILE_DIR:-}" ]]; then
    printf '%s/home-manager\n' "${NIXOS_CONFIG_HM_PROFILE_DIR%/}"
    return
  fi

  local state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
  local user_profiles="$state_home/nix/profiles"
  local global_profiles="${NIX_STATE_DIR:-/nix/var/nix}/profiles/per-user/$USER"
  if [[ -d "$user_profiles" ]]; then
    printf '%s/home-manager\n' "$user_profiles"
  elif [[ -d "$global_profiles" ]]; then
    printf '%s/home-manager\n' "$global_profiles"
  else
    fail "Home Manager no encontró un directorio de perfiles en $user_profiles ni $global_profiles"
  fi
}

validate_store_path() {
  local candidate=$1
  local kind=$2
  [[ "$candidate" == "$store_root/"* && -d "$candidate" ]] \
    || fail "$kind no es un path válido del store: ${candidate:-vacío}"
}

validate_home_generation() {
  local candidate=$1
  validate_store_path "$candidate" "la generación de Home Manager"
  [[ -x "$candidate/activate" && -f "$candidate/gen-version" ]] \
    || fail "la generación de Home Manager no tiene activate/gen-version: $candidate"
}

validate_system_generation() {
  local candidate=$1
  validate_store_path "$candidate" "la generación NixOS"
  [[ -x "$candidate/bin/switch-to-configuration" ]] \
    || fail "la generación NixOS no contiene switch-to-configuration: $candidate"
}

create_operation() {
  local source_dir=$1
  local state_root="${NIXOS_CONFIG_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/nixos-config}"
  local operation_id
  operation_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  umask 077
  mkdir -p -- "$state_root/operations"
  chmod 700 -- "$state_root" "$state_root/operations"
  operation_dir="$state_root/operations/$operation_id"
  mkdir -- "$operation_dir"
  manifest="$operation_dir/manifest"
  operation_status="created"
  failure_phase=""
  system_previous=""
  system_candidate=""
  home_profile="$(home_manager_profile)"
  home_previous="$(readlink -f "$home_profile" 2>/dev/null || true)"
  home_candidate=""
  source_revision="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || printf unknown)"
  source_digest="$(
    nix --extra-experimental-features "$required_nix_features" hash path "$source_dir"
  )"
}

write_manifest() {
  local temporary_manifest="$manifest.tmp"
  local manifest_value
  for manifest_value in \
    "$operation_status" "$failure_phase" "$source_revision" \
    "$source_digest" \
    "$system_previous" "$system_candidate" "$home_profile" \
    "$home_previous" "$home_candidate"; do
    case "$manifest_value" in
      *$'\n'*|*$'\r'*) fail "un valor del manifiesto contiene un salto de línea" ;;
    esac
  done
  {
    printf 'version=1\n'
    printf 'status=%s\n' "$operation_status"
    printf 'failure_phase=%s\n' "$failure_phase"
    printf 'source_revision=%s\n' "$source_revision"
    printf 'source_digest=%s\n' "$source_digest"
    printf 'system_previous=%s\n' "$system_previous"
    printf 'system_candidate=%s\n' "$system_candidate"
    printf 'home_profile=%s\n' "$home_profile"
    printf 'home_previous=%s\n' "$home_previous"
    printf 'home_candidate=%s\n' "$home_candidate"
  } > "$temporary_manifest"
  chmod 600 -- "$temporary_manifest"
  mv -f -- "$temporary_manifest" "$manifest"
}

report_recovery() {
  echo "La operación no se completó. El estado quedó registrado en:" >&2
  echo "  $manifest" >&2
  echo "Recovery explícito:" >&2
  printf '  ./install.sh recover %q\n' "$manifest" >&2
}

build_home_candidate() {
  local source_dir=$1
  nix --extra-experimental-features "$required_nix_features" \
    build "path:$source_dir#homeConfigurations.default.activationPackage" \
    --out-link "$operation_dir/home-result"
  home_candidate="$(readlink -f "$operation_dir/home-result")"
  validate_home_generation "$home_candidate"
}

activate_home_candidate() {
  validate_home_generation "$home_candidate"
  mkdir -p -- "$(dirname -- "$home_profile")"
  nix-env --profile "$home_profile" --set "$home_candidate"
  HOME_MANAGER_BACKUP_EXT=hm-bak "$home_candidate/activate" --driver-version 1
}

activate_system_generation() {
  local generation=$1
  validate_system_generation "$generation"
  sudo env \
    "NIX_CONFIG=experimental-features = $required_nix_features" \
    nixos-rebuild switch \
    --no-reexec \
    --store-path "$generation" \
    --option experimental-features "$required_nix_features"
}

build_system_candidate() {
  local source_dir=$1
  local configuration_file=$2
  env "NIXOS_EXISTING_CONFIGURATION=$configuration_file" \
    nix --extra-experimental-features "$required_nix_features" \
    build --impure \
    "path:$source_dir#nixosConfigurations.existing.config.system.build.toplevel" \
    --out-link "$operation_dir/nixos-result"
  system_candidate="$(readlink -f "$operation_dir/nixos-result")"
  validate_system_generation "$system_candidate"
}

install_home_manager() (
  configure_inventory_if_needed

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    fail "Home Manager debe aplicarse como usuario normal, sin sudo"
  fi
  for command_name in git nix nix-env; do
    command -v "$command_name" >/dev/null 2>&1 || fail "no se encontró el comando $command_name"
  done

  echo "==> Verificando que Home Manager no administre el sistema..." >&2
  bash "$repo_dir/verify-user-only.sh"

  source_dir="$(prepare_flake_source)"
  trap 'cleanup_flake_source "$source_dir"' EXIT
  create_operation "$source_dir"
  write_manifest

  echo "==> Construyendo una generación exacta de Home Manager..." >&2
  if ! build_home_candidate "$source_dir"; then
    operation_status="failed"
    failure_phase="home-build"
    write_manifest
    report_recovery
    return 1
  fi
  operation_status="prepared"
  write_manifest

  echo "==> Activando exactamente $home_candidate..." >&2
  operation_status="activating-home"
  write_manifest
  if ! activate_home_candidate; then
    operation_status="failed"
    failure_phase="home-activation"
    write_manifest
    report_recovery
    return 1
  fi

  operation_status="complete"
  write_manifest
  echo "Home Manager quedó aplicado. Manifiesto: $manifest" >&2
)

reload_holodeck_control() {
  if ! command -v noctalia >/dev/null 2>&1; then
    fail "Home Manager quedó aplicado, pero no se encontró el comando noctalia para recargar Holodeck Control"
  fi

  echo "==> Recargando Holodeck Control en Noctalia..." >&2
  noctalia msg plugins disable holodeck/control
  noctalia msg plugins enable holodeck/control
  echo "Holodeck quedó regenerado y el plugin fue recargado." >&2
}

regenerate_holodeck() {
  install_home_manager
  reload_holodeck_control
}

install_existing_nixos() (
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    fail "la instalación completa debe ejecutarse como usuario normal, sin sudo"
  fi

  configure_inventory_if_needed

  echo "==> Verificando los límites de sistema y Home Manager..." >&2
  bash "$repo_dir/verify-no-desktop.sh"
  bash "$repo_dir/verify-user-only.sh"
  bash "$repo_dir/apply-nixos-system.sh" validate

  for command_name in git nix nix-env nixos-rebuild sudo; do
    command -v "$command_name" >/dev/null 2>&1 || fail "no se encontró el comando $command_name"
  done

  system_root="${NIXOS_CONFIG_SYSTEM_ROOT:-/}"
  configuration_file="${NIXOS_EXISTING_CONFIGURATION:-${system_root%/}/etc/nixos/configuration.nix}"
  current_system="${system_root%/}/run/current-system"
  if [[ "$system_root" == "/" ]]; then
    current_system="/run/current-system"
  fi

  source_dir="$(prepare_flake_source)"
  trap 'cleanup_flake_source "$source_dir"' EXIT
  create_operation "$source_dir"
  system_previous="$(readlink -f "$current_system" 2>/dev/null || true)"
  validate_system_generation "$system_previous"
  write_manifest

  echo "==> Construyendo candidatos exactos de NixOS y Home Manager..." >&2
  if ! build_system_candidate "$source_dir" "$configuration_file"; then
    operation_status="failed"
    failure_phase="nixos-build"
    write_manifest
    report_recovery
    return 1
  fi
  if ! build_home_candidate "$source_dir"; then
    operation_status="failed"
    failure_phase="home-build"
    write_manifest
    report_recovery
    return 1
  fi
  operation_status="prepared"
  write_manifest

  echo "==> Activando exactamente $system_candidate..." >&2
  operation_status="activating-system"
  write_manifest
  if ! activate_system_generation "$system_candidate"; then
    operation_status="failed"
    failure_phase="nixos-activation"
    write_manifest
    report_recovery
    return 1
  fi
  operation_status="system-active"
  write_manifest

  echo "==> Activando exactamente $home_candidate..." >&2
  operation_status="activating-home"
  write_manifest
  if ! activate_home_candidate; then
    operation_status="failed"
    failure_phase="home-activation"
    write_manifest
    report_recovery
    return 1
  fi

  operation_status="complete"
  write_manifest

  echo "Instalación completa. Cerrá la sesión de KDE para entrar a Niri." >&2
  echo "Manifiesto: $manifest" >&2
)

load_manifest() {
  manifest=$1
  [[ -f "$manifest" && ! -L "$manifest" ]] || fail "manifiesto inválido: $manifest"
  [[ -O "$manifest" ]] || fail "el manifiesto no pertenece al usuario actual: $manifest"
  manifest_mode="$(stat -c '%a' "$manifest")"
  [[ "$manifest_mode" == "600" ]] || fail "el manifiesto debe ser privado (modo 600): $manifest"

  local manifest_version=""
  operation_status=""
  failure_phase=""
  source_revision=""
  source_digest=""
  system_previous=""
  system_candidate=""
  home_profile=""
  home_previous=""
  home_candidate=""

  while IFS='=' read -r key value; do
    case "$key" in
      version) manifest_version=$value ;;
      status) operation_status=$value ;;
      failure_phase) failure_phase=$value ;;
      source_revision) source_revision=$value ;;
      source_digest) source_digest=$value ;;
      system_previous) system_previous=$value ;;
      system_candidate) system_candidate=$value ;;
      home_profile) home_profile=$value ;;
      home_previous) home_previous=$value ;;
      home_candidate) home_candidate=$value ;;
      *) fail "clave desconocida en el manifiesto: $key" ;;
    esac
  done < "$manifest"

  [[ "$manifest_version" == "1" ]] || fail "versión de manifiesto no soportada: $manifest_version"
  [[ -n "$operation_status" && -n "$home_profile" ]] || fail "manifiesto incompleto: $manifest"
  operation_dir="$(dirname -- "$manifest")"
}

recover_operation() (
  [[ $# -eq 1 ]] || fail "recover requiere la ruta exacta de un manifiesto"
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    fail "recovery debe ejecutarse como usuario normal, sin sudo"
  fi

  load_manifest "$1"
  if [[ "$operation_status" == "recovered" ]]; then
    echo "La operación ya fue recuperada: $manifest" >&2
    return 0
  fi

  if [[ -n "$home_previous" ]]; then
    command -v nix-env >/dev/null 2>&1 || fail "no se encontró el comando nix-env"
    validate_home_generation "$home_previous"
    echo "==> Restaurando Home Manager a $home_previous..." >&2
    operation_status="recovering-home"
    failure_phase=""
    write_manifest
    if ! nix-env --profile "$home_profile" --set "$home_previous"; then
      operation_status="recovery-failed"
      failure_phase="home-profile-rollback"
      write_manifest
      return 1
    fi
    if ! HOME_MANAGER_BACKUP_EXT=hm-recovery-bak \
      "$home_previous/activate" --driver-version 1; then
      operation_status="recovery-failed"
      failure_phase="home-rollback-activation"
      write_manifest
      return 1
    fi
  elif [[ -z "$system_previous" ]]; then
    fail "el manifiesto no contiene una generación previa recuperable"
  fi

  if [[ -n "$system_previous" ]]; then
    for command_name in nixos-rebuild sudo; do
      command -v "$command_name" >/dev/null 2>&1 || fail "no se encontró el comando $command_name"
    done
    validate_system_generation "$system_previous"
    echo "==> Restaurando NixOS a $system_previous..." >&2
    operation_status="recovering-system"
    write_manifest
    if ! activate_system_generation "$system_previous"; then
      operation_status="recovery-failed"
      failure_phase="nixos-rollback-activation"
      write_manifest
      return 1
    fi
  fi

  operation_status="recovered"
  failure_phase=""
  write_manifest
  echo "Recovery completado. Manifiesto: $manifest" >&2
)

case "${1:-}" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

if [[ $# -gt 0 ]]; then
  backend="$1"
  shift
else
  backend="$(choose_backend)"
fi

case "$backend" in
  configure|config|detect)
    exec bash "$repo_dir/configure-inventory.sh" "$@"
    ;;
  existing|existing-nixos)
    if [[ $# -ne 0 ]]; then
      fail "existing-nixos no acepta argumentos adicionales"
    fi
    install_existing_nixos
    ;;
  home|home-manager)
    if [[ $# -ne 0 ]]; then
      fail "home-manager no acepta argumentos adicionales"
    fi
    install_home_manager
    ;;
  recover)
    recover_operation "$@"
    ;;
  regenerate|holodeck-regenerate)
    if [[ $# -ne 0 ]]; then
      fail "regenerate no acepta argumentos adicionales"
    fi
    regenerate_holodeck
    ;;
  nix-os|nixos)
    target="wsl"
    if [[ $# -gt 0 && "$1" != -* ]]; then
      target="$1"
      shift
    fi

    case "$target" in
      existing|existing-nixos)
        if [[ $# -ne 0 ]]; then
          fail "existing-nixos no acepta argumentos adicionales"
        fi
        install_existing_nixos
        exit 0
        ;;
      home|home-manager)
        if [[ $# -ne 0 ]]; then
          fail "home-manager no acepta argumentos adicionales"
        fi
        install_home_manager
        exit 0
        ;;
      wsl) ;;
      *) fail "target NixOS desconocido: $target (usá existing, home-manager o wsl)" ;;
    esac

    if ! command -v nix >/dev/null 2>&1; then
      fail "el backend NixOS requiere el comando nix"
    fi

    configure_inventory_if_needed

    source_dir="$(prepare_flake_source)"
    trap 'cleanup_flake_source "$source_dir"' EXIT
    cd "$source_dir"
    nix_command=(
      nix
      --extra-experimental-features "nix-command flakes"
      run "path:$source_dir#holodeck-system-nixos" --
      install
      --target wsl
      --repo "$repo_dir"
      "$@"
    )
    NIXOS_CONFIG_FLAKE_SOURCE="$source_dir" "${nix_command[@]}"
    ;;
  *)
    if [[ ! "$backend" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
      fail "ID de backend inválido: $backend"
    fi

    backend_command="holodeck-system-$backend"
    if command -v "$backend_command" >/dev/null 2>&1; then
      exec "$backend_command" install --repo "$repo_dir" "$@"
    fi

    if command -v nix >/dev/null 2>&1; then
      source_dir="$(prepare_flake_source)"
      trap 'cleanup_flake_source "$source_dir"' EXIT
      cd "$source_dir"
      nix_command=(
        nix
        --extra-experimental-features "nix-command flakes"
        run "path:$source_dir#$backend_command" --
        install
        --repo "$repo_dir"
        "$@"
      )
      NIXOS_CONFIG_FLAKE_SOURCE="$source_dir" "${nix_command[@]}"
      exit $?
    fi

    fail "backend no instalado: $backend_command"
    ;;
esac
