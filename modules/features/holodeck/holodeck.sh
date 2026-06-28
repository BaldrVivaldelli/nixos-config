set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
holodeck_dir="$config_home/holodeck"
profiles_dir="$holodeck_dir/profiles"
git_profiles_dir="$holodeck_dir/git"
public_keys_dir="$holodeck_dir/public-keys"
gitconfig_file="$HOME/.gitconfig"
ssh_config_file="$HOME/.ssh/config"

git_begin="# >>> holodeck git"
git_end="# <<< holodeck git"
ssh_begin="# >>> holodeck ssh"
ssh_end="# <<< holodeck ssh"

usage() {
  cat <<'USAGE'
Usage: holodeck <command>

Recommended first run:
  holodeck setup        Full wizard: auth + SSH/GPG + Git profiles

Commands:
  setup                 Full wizard for GitHub personal and/or GitLab work
  github                Configure GitHub from your authenticated account
  gitlab                Configure one GitLab profile
  login github          Only authenticate GitHub; does not configure Git
  login gitlab          Only authenticate GitLab; does not configure Git
  auth github           Alias for login github
  auth gitlab           Alias for login gitlab
  profile github        Alias for github
  profile gitlab        Alias for gitlab
  doctor                Show profiles, auth state, and key files
  purge                 Remove Holodeck-managed local profiles, keys, and auth
  clean                 Alias for purge
  sanitize              Alias for purge

Holodeck stores generated local state under ~/.config/holodeck and only writes
managed blocks in ~/.gitconfig and ~/.ssh/config.
USAGE
}

ensure_dirs() {
  mkdir -p "$profiles_dir" "$git_profiles_dir" "$public_keys_dir" "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
}

prompt() {
  local label default value
  label="$1"
  default="${2:-}"

  if [ -n "$default" ]; then
    read -r -p "$label [$default]: " value
    printf '%s\n' "${value:-$default}"
  else
    read -r -p "$label: " value
    printf '%s\n' "$value"
  fi
}

confirm() {
  local label default answer
  label="$1"
  default="${2:-yes}"

  if [ "$default" = "yes" ]; then
    read -r -p "$label [Y/n]: " answer
    case "${answer:-y}" in
      y|Y|yes|YES) return 0 ;;
      *) return 1 ;;
    esac
  else
    read -r -p "$label [y/N]: " answer
    case "${answer:-n}" in
      y|Y|yes|YES) return 0 ;;
      *) return 1 ;;
    esac
  fi
}

expand_path() {
  local value
  value="$1"

  case "$value" in
    \~) printf '%s\n' "$HOME" ;;
    \~/*) printf '%s/%s\n' "$HOME" "${value#\~/}" ;;
    \$HOME) printf '%s\n' "$HOME" ;;
    \$HOME/*) printf '%s/%s\n' "$HOME" "${value#\$HOME/}" ;;
    *) printf '%s\n' "$value" ;;
  esac
}

sanitize_id() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9_-]/-/g; s/^-*//; s/-*$//'
}

env_line() {
  local key value
  key="$1"
  value="$2"
  printf '%s=%q\n' "$key" "$value"
}

profile_file_for() {
  printf '%s/%s.env\n' "$profiles_dir" "$1"
}

git_profile_file_for() {
  printf '%s/%s.gitconfig\n' "$git_profiles_dir" "$1"
}

ssh_key_file_for() {
  printf '%s/.ssh/holodeck_%s_%s\n' "$HOME" "$1" "$2"
}

remove_managed_block() {
  local file begin end tmp
  file="$1"
  begin="$2"
  end="$3"

  [ -f "$file" ] || return 0

  tmp="$(mktemp)"
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    skip != 1 { print }
  ' "$file" > "$tmp"

  cp "$file" "$file.holodeck.bak"
  mv "$tmp" "$file"
}

profile_files() {
  [ -d "$profiles_dir" ] || return 0
  find "$profiles_dir" -maxdepth 1 -type f -name '*.env' 2>/dev/null | sort
}

rebuild_gitconfig_block() {
  local tmp file path

  ensure_dirs
  remove_managed_block "$gitconfig_file" "$git_begin" "$git_end"
  tmp="$(mktemp)"

  {
    echo "$git_begin"
    for file in $(profile_files); do
      # shellcheck disable=SC1090
      source "$file"
      path="$(git_profile_file_for "$HOLODECK_PROFILE")"

      if [ -n "${HOLODECK_PROJECTS_DIR:-}" ] && [ -f "$path" ]; then
        printf '[includeIf "gitdir:%s/**"]\n' "$HOLODECK_PROJECTS_DIR"
        printf '  path = %s\n' "$path"
        echo
      fi
    done
    echo "$git_end"
  } > "$tmp"

  if grep -q '^\[includeIf ' "$tmp"; then
    touch "$gitconfig_file"
    cat "$tmp" >> "$gitconfig_file"
  fi

  rm -f "$tmp"
}

rebuild_ssh_config_block() {
  local tmp file

  ensure_dirs
  remove_managed_block "$ssh_config_file" "$ssh_begin" "$ssh_end"
  tmp="$(mktemp)"

  {
    echo "$ssh_begin"
    for file in $(profile_files); do
      # shellcheck disable=SC1090
      source "$file"

      if [ -n "${HOLODECK_HOST:-}" ] && [ -n "${HOLODECK_SSH_KEY:-}" ]; then
        printf 'Host %s\n' "$HOLODECK_HOST"
        printf '  HostName %s\n' "$HOLODECK_HOST"
        printf '  User git\n'
        printf '  IdentityFile %s\n' "$HOLODECK_SSH_KEY"
        printf '  IdentitiesOnly yes\n'
        echo
      fi
    done
    echo "$ssh_end"
  } > "$tmp"

  if grep -q '^Host ' "$tmp"; then
    touch "$ssh_config_file"
    chmod 600 "$ssh_config_file"
    cat "$tmp" >> "$ssh_config_file"
  fi

  rm -f "$tmp"
}

find_gpg_fingerprint() {
  local email
  email="$1"

  gpg --list-secret-keys --with-colons "$email" 2>/dev/null \
    | awk -F: '$1 == "fpr" { print $10; exit }'
}

is_gpg_fingerprint() {
  printf '%s\n' "$1" | grep -Eq '^[A-Fa-f0-9]{40,}$'
}

ensure_gpg_key() {
  local name email mode fingerprint user_id
  name="$1"
  email="$2"
  mode="${3:-prompt}"

  fingerprint="$(find_gpg_fingerprint "$email")"
  if [ -n "$fingerprint" ]; then
    echo "Using existing GPG key for $email: $fingerprint" >&2
    printf '%s\n' "$fingerprint"
    return 0
  fi

  if [ "$mode" = "prompt" ] && ! confirm "Generate a new GPG signing key for $email?" yes; then
    return 0
  fi

  user_id="$name <$email>"
  echo "Generating GPG key for $user_id" >&2
  echo "GPG may ask for a passphrase in a pinentry dialog." >&2
  gpg --quick-generate-key "$user_id" ed25519 sign 2y >&2

  fingerprint="$(find_gpg_fingerprint "$email")"
  if [ -n "$fingerprint" ]; then
    printf '%s\n' "$fingerprint"
  fi
}

write_git_profile() {
  local profile name email fingerprint git_file
  profile="$1"
  name="$2"
  email="$3"
  fingerprint="$4"
  git_file="$(git_profile_file_for "$profile")"

  {
    echo "[user]"
    printf "  name = %s\n" "$name"
    printf "  email = %s\n" "$email"
    if [ -n "$fingerprint" ]; then
      printf "  signingKey = %s\n" "$fingerprint"
    fi
    echo
    echo "[init]"
    echo "  defaultBranch = main"
    if [ -n "$fingerprint" ]; then
      echo
      echo "[commit]"
      echo "  gpgSign = true"
      echo
      echo "[tag]"
      echo "  gpgSign = true"
      echo
      echo "[gpg]"
      echo "  program = gpg"
    fi
  } > "$git_file"
}

generate_ssh_key() {
  local ssh_key email mode
  ssh_key="$1"
  email="$2"
  mode="${3:-prompt}"

  if [ -f "$ssh_key" ]; then
    echo "Using existing SSH key: $ssh_key"
    return 0
  fi

  echo "Generating SSH key: $ssh_key"
  if [ "$mode" = "auto" ]; then
    ssh-keygen -t ed25519 -C "$email" -f "$ssh_key" -N ""
  else
    ssh-keygen -t ed25519 -C "$email" -f "$ssh_key"
  fi
}

login_github() {
  local host
  host="$1"

  if gh auth status --hostname "$host" >/dev/null 2>&1; then
    echo "GitHub is already authenticated on $host."
    return 0
  fi

  gh auth login --hostname "$host" --web --git-protocol ssh
}

login_gitlab() {
  local host
  host="$1"

  if glab auth status --hostname "$host" >/dev/null 2>&1; then
    echo "GitLab is already authenticated on $host."
    return 0
  fi

  if glab auth login --hostname "$host" --web; then
    return 0
  fi

  echo "GitLab web login was not available; falling back to glab interactive login."
  glab auth login --hostname "$host"
}

login_provider() {
  local provider host
  provider="$1"
  host="$2"

  case "$provider" in
    github) login_github "$host" ;;
    gitlab) login_gitlab "$host" ;;
    *) echo "Unknown provider: $provider" >&2; return 1 ;;
  esac
}

upload_keys() {
  local provider host title ssh_pub gpg_pub
  provider="$1"
  host="$2"
  title="$3"
  ssh_pub="$4"
  gpg_pub="$5"

  case "$provider" in
    github)
      if [ -f "$ssh_pub" ]; then
        gh ssh-key add "$ssh_pub" --title "$title" || true
      fi
      if [ -f "$gpg_pub" ]; then
        upload_github_gpg_key "$host" "$gpg_pub"
      fi
      ;;
    gitlab)
      if [ -f "$ssh_pub" ]; then
        glab ssh-key add "$ssh_pub" --title "$title" || true
      fi
      if [ -f "$gpg_pub" ]; then
        if glab gpg-key add --help >/dev/null 2>&1; then
          glab gpg-key add "$gpg_pub" || true
        else
          echo "glab does not expose gpg-key add here. Opening GitLab GPG settings."
          xdg-open "https://$host/-/user_settings/gpg_keys" >/dev/null 2>&1 || true
          echo "Public GPG key: $gpg_pub"
        fi
      fi
      ;;
  esac
}

upload_github_gpg_key() {
  local host gpg_pub error_file
  host="$1"
  gpg_pub="$2"

  error_file="$(mktemp)"
  if gh gpg-key add "$gpg_pub" 2>"$error_file"; then
    rm -f "$error_file"
    return 0
  fi

  if grep -qi 'insufficient OAuth scopes' "$error_file"; then
    rm -f "$error_file"
    echo "GitHub requires the write:gpg_key scope before Holodeck can upload your GPG key."
    echo "Opening GitHub auth refresh for that scope..."

    if gh auth refresh --hostname "$host" --scopes write:gpg_key; then
      gh gpg-key add "$gpg_pub" || true
      return 0
    fi

    echo "GitHub did not grant the extra scope automatically."
    echo "Run this when you want to upload the GPG key:"
    echo "  gh auth refresh --hostname $host --scopes write:gpg_key"
    echo "  gh gpg-key add $gpg_pub"
    return 0
  fi

  cat "$error_file" >&2
  rm -f "$error_file"
  return 0
}

write_local_profile() {
  local provider profile host projects_dir_abs name email auth_ok ssh_mode gpg_mode upload_mode
  local ssh_key ssh_pub fingerprint gpg_pub profile_file title

  provider="$1"
  profile="$2"
  host="$3"
  projects_dir_abs="$4"
  name="$5"
  email="$6"
  auth_ok="$7"
  ssh_mode="${8:-prompt}"
  gpg_mode="${9:-prompt}"
  upload_mode="${10:-prompt}"

  ensure_dirs
  mkdir -p "$projects_dir_abs"

  if [ -z "$profile" ]; then
    echo "Invalid profile name." >&2
    exit 1
  fi
  if [ -z "$name" ] || [ -z "$email" ]; then
    echo "Name and email are required." >&2
    exit 1
  fi

  ssh_key="$(ssh_key_file_for "$profile" "$provider")"
  generate_ssh_key "$ssh_key" "$email" "$ssh_mode"
  chmod 600 "$ssh_key"
  ssh_pub="$ssh_key.pub"

  fingerprint="$(ensure_gpg_key "$name" "$email" "$gpg_mode" || true)"
  gpg_pub=""
  if [ -n "$fingerprint" ] && is_gpg_fingerprint "$fingerprint"; then
    gpg_pub="$public_keys_dir/$profile-gpg.asc"
    if ! gpg --armor --export "$fingerprint" > "$gpg_pub"; then
      echo "Could not export GPG public key for $fingerprint." >&2
      gpg_pub=""
    fi
  elif [ -n "$fingerprint" ]; then
    echo "Ignoring invalid GPG fingerprint: $fingerprint" >&2
    fingerprint=""
  fi

  write_git_profile "$profile" "$name" "$email" "$fingerprint"

  profile_file="$(profile_file_for "$profile")"
  {
    env_line HOLODECK_PROFILE "$profile"
    env_line HOLODECK_PROVIDER "$provider"
    env_line HOLODECK_HOST "$host"
    env_line HOLODECK_PROJECTS_DIR "$projects_dir_abs"
    env_line HOLODECK_NAME "$name"
    env_line HOLODECK_EMAIL "$email"
    env_line HOLODECK_SSH_KEY "$ssh_key"
    env_line HOLODECK_GPG_FINGERPRINT "$fingerprint"
  } > "$profile_file"

  rebuild_gitconfig_block
  rebuild_ssh_config_block

  title="holodeck-$profile@$(hostname)"
  if [ "$auth_ok" = "1" ] && { [ "$upload_mode" = "auto" ] || confirm "Upload SSH/GPG public keys to $provider?" yes; }; then
    upload_keys "$provider" "$host" "$title" "$ssh_pub" "$gpg_pub"
  fi

  echo
  echo "Profile configured: $profile"
  echo "Projects: $projects_dir_abs"
  echo "Git config: $(git_profile_file_for "$profile")"
}

configure_profile() {
  local provider default_profile default_host default_dir raw_profile profile host projects_dir projects_dir_abs
  local name email auth_ok

  provider="$1"
  default_profile="$2"
  default_host="$3"
  default_dir="$4"

  raw_profile="$(prompt "Profile name" "$default_profile")"
  profile="$(sanitize_id "$raw_profile")"
  if [ -z "$profile" ]; then
    echo "Invalid profile name." >&2
    exit 1
  fi

  host="$(prompt "Host" "$default_host")"
  projects_dir="$(prompt "Projects directory for this profile" "$default_dir")"
  projects_dir_abs="$(expand_path "$projects_dir")"

  name="$(prompt "Git commit name" "$(git config --global user.name 2>/dev/null || true)")"
  email="$(prompt "Git commit email" "$(git config --global user.email 2>/dev/null || true)")"

  auth_ok=0
  if confirm "Authenticate $provider on $host now?" yes; then
    if login_provider "$provider" "$host"; then
      auth_ok=1
    else
      echo "Authentication failed or was cancelled. Continuing with local config only."
    fi
  fi

  write_local_profile "$provider" "$profile" "$host" "$projects_dir_abs" "$name" "$email" "$auth_ok" prompt prompt prompt
}

github_api_field() {
  local host field
  host="$1"
  field="$2"

  gh api --hostname "$host" user --jq ".$field // \"\"" 2>/dev/null || true
}

github_primary_email() {
  local host
  host="$1"

  gh api --hostname "$host" user/emails \
    --jq 'map(select(.primary == true and .verified == true))[0].email // ""' \
    2>/dev/null || true
}

github_noreply_email() {
  local login id
  login="$1"
  id="$2"

  if [ -n "$id" ]; then
    printf '%s+%s@users.noreply.github.com\n' "$id" "$login"
  else
    printf '%s@users.noreply.github.com\n' "$login"
  fi
}

configure_github_profile() {
  local host login id name email profile projects_dir_abs auth_ok

  host="$HOLODECK_DEFAULT_GITHUB_HOST"
  login_github "$host"
  auth_ok=1

  login="$(github_api_field "$host" login)"
  id="$(github_api_field "$host" id)"
  name="$(github_api_field "$host" name)"
  email="$(github_api_field "$host" email)"

  if [ -z "$login" ]; then
    echo "Could not read the GitHub account from gh." >&2
    exit 1
  fi

  if [ -z "$name" ]; then
    name="$login"
  fi

  if [ -z "$email" ]; then
    email="$(github_primary_email "$host")"
  fi

  if [ -z "$email" ]; then
    email="$(github_noreply_email "$login" "$id")"
  fi

  profile="$(sanitize_id "$login")"
  projects_dir_abs="$(expand_path "$HOLODECK_DEFAULT_PERSONAL_DIR")"

  echo "Using GitHub account: $login"
  echo "Git commit name: $name"
  echo "Git commit email: $email"
  echo "Projects directory: $projects_dir_abs"

  write_local_profile github "$profile" "$host" "$projects_dir_abs" "$name" "$email" "$auth_ok" auto auto auto
}

setup() {
  echo "Holodeck setup"
  echo

  if confirm "Configure GitHub personal profile?" yes; then
    configure_github_profile
  fi

  echo

  if confirm "Configure GitLab work profile?" yes; then
    configure_profile gitlab work "$HOLODECK_DEFAULT_GITLAB_HOST" "$HOLODECK_DEFAULT_WORK_DIR"
  fi
}

auth_command() {
  local provider host
  provider="${1:-}"

  case "$provider" in
    github) host="$(prompt "GitHub host" "$HOLODECK_DEFAULT_GITHUB_HOST")" ;;
    gitlab) host="$(prompt "GitLab host" "$HOLODECK_DEFAULT_GITLAB_HOST")" ;;
    *) usage; exit 1 ;;
  esac

  login_provider "$provider" "$host"
}

profile_command() {
  local provider
  provider="${1:-}"

  case "$provider" in
    github) configure_github_profile ;;
    gitlab) configure_profile gitlab work "$HOLODECK_DEFAULT_GITLAB_HOST" "$HOLODECK_DEFAULT_WORK_DIR" ;;
    *) usage; exit 1 ;;
  esac
}

doctor() {
  local file

  echo "Holodeck directory: $holodeck_dir"
  echo

  if [ ! -d "$profiles_dir" ] || [ -z "$(profile_files)" ]; then
    echo "No Holodeck profiles configured."
  else
    for file in $(profile_files); do
      # shellcheck disable=SC1090
      source "$file"
      echo "Profile: $HOLODECK_PROFILE"
      echo "  Provider: $HOLODECK_PROVIDER"
      echo "  Host: $HOLODECK_HOST"
      echo "  Projects: $HOLODECK_PROJECTS_DIR"
      echo "  Email: $HOLODECK_EMAIL"
      echo "  SSH key: $HOLODECK_SSH_KEY"
      echo "  GPG: ${HOLODECK_GPG_FINGERPRINT:-none}"
      echo
    done
  fi

  echo "GitHub auth:"
  gh auth status --hostname "$HOLODECK_DEFAULT_GITHUB_HOST" || true
  echo
  echo "GitLab auth:"
  glab auth status --hostname "$HOLODECK_DEFAULT_GITLAB_HOST" || true
}

logout_known_hosts() {
  local file host provider

  for file in $(profile_files); do
    # shellcheck disable=SC1090
    source "$file"
    host="${HOLODECK_HOST:-}"
    provider="${HOLODECK_PROVIDER:-}"

    case "$provider" in
      github)
        [ -n "$host" ] && gh auth logout --hostname "$host" --yes >/dev/null 2>&1 || true
        ;;
      gitlab)
        [ -n "$host" ] && yes | glab auth logout --hostname "$host" >/dev/null 2>&1 || true
        ;;
    esac
  done
}

delete_tracked_gpg_keys() {
  local file fingerprint

  for file in $(profile_files); do
    # shellcheck disable=SC1090
    source "$file"
    fingerprint="${HOLODECK_GPG_FINGERPRINT:-}"

    if [ -n "$fingerprint" ]; then
      echo "Deleting Holodeck-tracked GPG key: $fingerprint"
      gpg --batch --yes --delete-secret-and-public-key "$fingerprint" >/dev/null 2>&1 || true
    fi
  done
}

purge() {
  local answer

  echo "This removes local state managed by Holodeck:"
  echo "  - managed blocks in ~/.gitconfig and ~/.ssh/config"
  echo "  - ~/.config/holodeck"
  echo "  - ~/.ssh/holodeck_* keys"
  echo "  - Holodeck-tracked local GPG keys"
  echo "  - gh/glab local auth for Holodeck profile hosts"
  echo
  echo "It does not rewrite git history and does not remove uploaded public keys from GitHub/GitLab."
  echo
  read -r -p "Type 'purge holodeck' to continue: " answer

  if [ "$answer" != "purge holodeck" ]; then
    echo "Cancelled."
    exit 1
  fi

  logout_known_hosts
  delete_tracked_gpg_keys
  remove_managed_block "$gitconfig_file" "$git_begin" "$git_end"
  remove_managed_block "$ssh_config_file" "$ssh_begin" "$ssh_end"
  rm -f "$HOME"/.ssh/holodeck_*
  rm -rf "$holodeck_dir"

  echo "Holodeck local state removed."
}

case "${1:-help}" in
  setup)
    setup
    ;;
  github)
    profile_command github
    ;;
  gitlab)
    profile_command gitlab
    ;;
  auth|login)
    shift
    auth_command "${1:-}"
    ;;
  profile)
    shift
    profile_command "${1:-}"
    ;;
  doctor|status)
    doctor
    ;;
  purge|clean|sanitize)
    purge
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
