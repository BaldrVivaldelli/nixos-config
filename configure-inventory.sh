#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
output_file="$repo_dir/inventory.local.nix"
assume_yes=false
force=false
print_only=false

usage() {
  cat <<'MSG'
Uso:
  ./configure-inventory.sh
  ./configure-inventory.sh --yes
  ./configure-inventory.sh --print
  ./configure-inventory.sh --force

Detecta usuario, home, ruta del repositorio, hostname, arquitectura, zona
horaria y WSL. Muestra la propuesta antes de crear inventory.local.nix.

Opciones:
  -y, --yes       confirma la creación sin preguntar
  -f, --force     permite reemplazar un inventory.local.nix existente
  --print         imprime la propuesta sin escribir archivos
  --output RUTA   cambia el archivo de salida (útil para automatización)
  -h, --help      muestra esta ayuda

Para automatización se pueden definir NIXOS_CONFIG_USERNAME,
NIXOS_CONFIG_HOME, NIXOS_CONFIG_REPO, NIXOS_CONFIG_HOSTNAME,
NIXOS_CONFIG_SYSTEM, NIXOS_CONFIG_TIME_ZONE, NIXOS_CONFIG_OS,
NIXOS_CONFIG_ARCHITECTURE y NIXOS_CONFIG_IS_WSL.

Este proceso no consulta, monta, particiona ni modifica discos.
MSG
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      assume_yes=true
      ;;
    -f|--force)
      force=true
      ;;
    --print)
      print_only=true
      ;;
    --output)
      [[ $# -ge 2 ]] || fail "--output requiere una ruta"
      output_file="$2"
      shift
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      fail "opción desconocida: $1 (usá --help)"
      ;;
  esac
  shift
done

nix_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//\$\{/\\\$\{}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

detect_home() {
  local username="$1"
  local passwd_record=""
  local detected_home=""

  if command -v getent >/dev/null 2>&1; then
    passwd_record="$(getent passwd "$username" 2>/dev/null || true)"
  fi
  if [[ -n "$passwd_record" ]]; then
    IFS=: read -r _ _ _ _ _ detected_home _ <<< "$passwd_record"
  fi
  if [[ -z "$detected_home" ]]; then
    detected_home="${HOME:-}"
  fi
  printf '%s' "$detected_home"
}

detect_hostname() {
  local detected=""
  if command -v hostnamectl >/dev/null 2>&1; then
    detected="$(hostnamectl --static 2>/dev/null || true)"
  fi
  if [[ -z "$detected" ]] && command -v hostname >/dev/null 2>&1; then
    detected="$(hostname 2>/dev/null || true)"
  fi
  printf '%s' "${detected:-nixos}"
}

detect_timezone() {
  local detected=""
  local localtime_target=""
  if command -v timedatectl >/dev/null 2>&1; then
    detected="$(timedatectl show --property=Timezone --value 2>/dev/null || true)"
  fi
  if [[ -z "$detected" && -r /etc/timezone ]]; then
    IFS= read -r detected < /etc/timezone || true
  fi
  if [[ -z "$detected" && -e /etc/localtime ]]; then
    localtime_target="$(readlink -f /etc/localtime 2>/dev/null || true)"
    if [[ "$localtime_target" == */zoneinfo/* ]]; then
      detected="${localtime_target#*/zoneinfo/}"
    fi
  fi
  printf '%s' "${detected:-UTC}"
}

detect_os() {
  local key=""
  local value=""
  if [[ -r /etc/os-release ]]; then
    while IFS='=' read -r key value; do
      if [[ "$key" == "ID" ]]; then
        value="${value#\"}"
        value="${value%\"}"
        printf '%s' "$value"
        return
      fi
    done < /etc/os-release
  fi
  printf 'unknown'
}

detect_wsl() {
  local kernel_release=""
  if [[ -r /proc/sys/kernel/osrelease ]]; then
    IFS= read -r kernel_release < /proc/sys/kernel/osrelease || true
  fi
  if [[ "${kernel_release,,}" == *microsoft* || -n "${WSL_INTEROP:-}" || -n "${WSL_DISTRO_NAME:-}" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

map_nix_system() {
  local architecture="$1"
  local kernel_name="${2,,}"
  local platform=""
  case "$kernel_name" in
    linux) platform="linux" ;;
    darwin) platform="darwin" ;;
    *) fail "kernel no soportado para Nix: $2" ;;
  esac
  case "$architecture" in
    x86_64|amd64) printf 'x86_64-%s' "$platform" ;;
    aarch64|arm64) printf 'aarch64-%s' "$platform" ;;
    i386|i486|i586|i686) printf 'i686-%s' "$platform" ;;
    armv7l) printf 'armv7l-%s' "$platform" ;;
    *) fail "arquitectura no soportada para Nix: $architecture" ;;
  esac
}

username="${NIXOS_CONFIG_USERNAME:-$(id -un)}"
home_directory="${NIXOS_CONFIG_HOME:-$(detect_home "$username")}"
repo_path="${NIXOS_CONFIG_REPO:-$repo_dir}"
host_name="${NIXOS_CONFIG_HOSTNAME:-$(detect_hostname)}"
architecture="${NIXOS_CONFIG_ARCHITECTURE:-$(uname -m)}"
kernel_name="$(uname -s)"
system="${NIXOS_CONFIG_SYSTEM:-$(map_nix_system "$architecture" "$kernel_name")}"
time_zone="${NIXOS_CONFIG_TIME_ZONE:-$(detect_timezone)}"
os_id="${NIXOS_CONFIG_OS:-$(detect_os)}"
is_wsl="${NIXOS_CONFIG_IS_WSL:-$(detect_wsl)}"

[[ -n "$username" ]] || fail "no se pudo detectar el usuario"
[[ "$username" != *[$'\n\r:/']* ]] || fail "el usuario detectado no es válido: $username"
[[ "$home_directory" == /* ]] || fail "el home debe ser una ruta absoluta: $home_directory"
[[ "$repo_path" == /* ]] || fail "la ruta del repositorio debe ser absoluta: $repo_path"
[[ -n "$host_name" && "$host_name" != *[$'\n\r/']* ]] || fail "hostname detectado inválido"
[[ -n "$time_zone" && "$time_zone" != *[$'\n\r']* ]] || fail "zona horaria detectada inválida"
case "$is_wsl" in
  1|yes|true) is_wsl=true ;;
  0|no|false) is_wsl=false ;;
  *) fail "NIXOS_CONFIG_IS_WSL debe ser true o false" ;;
esac

repo_path="$(readlink -f -- "$repo_path")"
if [[ "$home_directory" != "/" ]]; then
  home_directory="${home_directory%/}"
fi
if command -v realpath >/dev/null 2>&1; then
  repo_relative_path="$(realpath --canonicalize-missing --relative-to="$home_directory" "$repo_path")"
elif [[ "$repo_path" == "$home_directory/"* ]]; then
  repo_relative_path="${repo_path#"$home_directory/"}"
else
  fail "se necesita realpath cuando el repositorio está fuera del home"
fi

escaped_username="$(nix_escape "$username")"
escaped_home="$(nix_escape "$home_directory")"
escaped_repo="$(nix_escape "$repo_path")"
escaped_repo_relative="$(nix_escape "$repo_relative_path")"
escaped_host="$(nix_escape "$host_name")"
escaped_architecture="$(nix_escape "$architecture")"
escaped_system="$(nix_escape "$system")"
escaped_timezone="$(nix_escape "$time_zone")"
escaped_os="$(nix_escape "$os_id")"

render_inventory() {
  printf '%s\n' \
    '{' \
    "  system = \"$escaped_system\";" \
    '' \
    '  machine = {' \
    "    os = \"$escaped_os\";" \
    "    architecture = \"$escaped_architecture\";" \
    "    hostName = \"$escaped_host\";" \
    "    timeZone = \"$escaped_timezone\";" \
    "    isWsl = $is_wsl;" \
    '  };' \
    '' \
    '  defaultHomeUser = "personal";' \
    '  users.personal = {' \
    "    username = \"$escaped_username\";" \
    "    homeDirectory = \"$escaped_home\";" \
    '    homeProfile = "developer";' \
    "    repoRelativePath = \"$escaped_repo_relative\";" \
    "    repoPath = \"$escaped_repo\";" \
    '  };' \
    '}'
}

if $print_only; then
  render_inventory
  exit 0
fi

echo "Características detectadas:" >&2
printf '  Sistema:      %s (%s, %s)\n' "$os_id" "$architecture" "$system" >&2
printf '  Usuario:      %s\n' "$username" >&2
printf '  Home:         %s\n' "$home_directory" >&2
printf '  Repositorio:  %s\n' "$repo_path" >&2
printf '  Hostname:     %s\n' "$host_name" >&2
printf '  Zona horaria: %s\n' "$time_zone" >&2
printf '  WSL:          %s\n' "$is_wsl" >&2
printf '  Destino:      %s\n' "$output_file" >&2

if [[ -e "$output_file" ]] && ! $force; then
  fail "$output_file ya existe; revisalo o usá --force para reemplazarlo"
fi

if ! $assume_yes; then
  [[ -t 0 ]] || fail "no hay una terminal para confirmar; usá --yes"
  printf '¿Crear este inventario local? [s/N]: ' >&2
  IFS= read -r confirmation
  case "$confirmation" in
    s|S|si|sí|Si|Sí|y|Y|yes|YES) ;;
    *)
      echo "Cancelado; no se modificó ningún archivo." >&2
      exit 1
      ;;
  esac
fi

output_directory="$(dirname -- "$output_file")"
[[ -d "$output_directory" ]] || fail "el directorio de salida no existe: $output_directory"
temporary_file="$(mktemp "$output_directory/.inventory.local.nix.XXXXXX")"
trap 'rm -f -- "$temporary_file"' EXIT
render_inventory > "$temporary_file"
mv -- "$temporary_file" "$output_file"
trap - EXIT

echo "Inventario local creado en $output_file." >&2
