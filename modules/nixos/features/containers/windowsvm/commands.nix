{
  config,
  lib,
  pkgs,
  ...
}:

let
  vm = config.features.containers.windowsVm;

  windowsVmCommand = pkgs.writeShellApplication {
    name = "windowsvm";
    runtimeInputs = [
      config.virtualisation.docker.package
      pkgs.bash
      pkgs.coreutils
      pkgs.freerdp
      pkgs.glibc.bin
      pkgs.guestfs-tools
      pkgs.gnutar
      pkgs.jq
      pkgs.shadow
      pkgs.xdg-utils
    ];
    text = ''
      set -euo pipefail

      original_args=("$@")

      container_name=$(printf '%s' ${lib.escapeShellArg vm.containerName})
      image=$(printf '%s' ${lib.escapeShellArg vm.image})
      version=$(printf '%s' ${lib.escapeShellArg vm.version})
      cpu_cores=${toString vm.cpuCores}
      ram_size=$(printf '%s' ${lib.escapeShellArg vm.ramSize})
      disk_size=$(printf '%s' ${lib.escapeShellArg vm.diskSize})
      default_username=$(printf '%s' ${lib.escapeShellArg vm.username})
      language=$(printf '%s' ${lib.escapeShellArg vm.language})
      region=$(printf '%s' ${lib.escapeShellArg vm.region})
      keyboard=$(printf '%s' ${lib.escapeShellArg vm.keyboard})
      bind_address=$(printf '%s' ${lib.escapeShellArg vm.bindAddress})
      web_port=${toString vm.webPort}
      rdp_port=${toString vm.rdpPort}
      declared_image_file=${lib.escapeShellArg vm.imageFile}
      firstboot_tools_dir=${lib.escapeShellArg "${pkgs.pkgsCross.mingwW64.rhsrvany}/bin"}

      storage_dir=''${WINDOWSVM_STORAGE:-$HOME/containers/windows/storage}
      shared_dir=''${WINDOWSVM_SHARED:-$HOME/containers/windows/shared}
      version=''${WINDOWSVM_VERSION:-$version}
      cpu_cores=''${WINDOWSVM_CPU_CORES:-$cpu_cores}
      ram_size=''${WINDOWSVM_RAM_SIZE:-$ram_size}
      disk_size=''${WINDOWSVM_DISK_SIZE:-$disk_size}
      username=''${WINDOWSVM_USER:-$default_username}
      password=""
      language=''${WINDOWSVM_LANGUAGE:-$language}
      region=''${WINDOWSVM_REGION:-$region}
      keyboard=''${WINDOWSVM_KEYBOARD:-$keyboard}
      rdp_timeout=''${WINDOWSVM_RDP_TIMEOUT:-90}
      rdp_attempts=''${WINDOWSVM_RDP_ATTEMPTS:-10}
      rdp_display_mode=''${WINDOWSVM_RDP_DISPLAY_MODE:-half}
      password_reset_timeout=''${WINDOWSVM_PASSWORD_RESET_TIMEOUT:-240}
      container_created=0

      has_active_docker_group() {
        [[ " $(id -nG) " == *" docker "* ]]
      }

      has_declared_docker_group() {
        local current_user
        current_user=$(id -un)

        [[ " $(id -nG "$current_user" 2>/dev/null || id -nG) " == *" docker "* ]]
      }

      reexec_with_docker_group() {
        local sg_bin
        local command

        if [ "''${WINDOWSVM_DOCKER_GROUP_REEXEC:-0}" = "1" ]; then
          return 1
        fi

        if has_active_docker_group || ! has_declared_docker_group; then
          return 1
        fi

        sg_bin=/run/wrappers/bin/sg
        if [ ! -x "$sg_bin" ]; then
          sg_bin=sg
        fi

        printf -v command 'WINDOWSVM_DOCKER_GROUP_REEXEC=1 %q' "$0"
        for arg in "''${original_args[@]}"; do
          printf -v command '%s %q' "$command" "$arg"
        done

        echo "Current session has not picked up the docker group yet; re-running this command with docker as the active group."
        exec "$sg_bin" docker -c "$command"
      }

      usage() {
        cat <<'USAGE'
      Usage: windowsvm <command> [rdp-display-mode]

      Commands:
        up       Start the Dockurr Windows container and open half or fullscreen RDP
        start    Start the container without opening a client
        rdp      Open FreeRDP in half or fullscreen mode
        web      Open the Dockurr web viewer
        password-reset
                 Replace the existing local Windows password without deleting its disk
        wipe     Irreversibly delete the Windows guest disk and create a fresh VM
        status   Show the Docker container status
        logs     Follow container logs
        down     Stop the container
        rm       Stop and remove the container

      Environment:
        WINDOWSVM_STORAGE      Host storage directory
        WINDOWSVM_SHARED       Host shared directory mounted as C:\Shared
        WINDOWSVM_VERSION      Dockurr Windows version
        WINDOWSVM_CPU_CORES    CPU cores assigned to the VM
        WINDOWSVM_RAM_SIZE     RAM assigned to the VM
        WINDOWSVM_DISK_SIZE    Disk size assigned to the VM
        WINDOWSVM_USER         RDP username, default Docker
        WINDOWSVM_PASSWORD     RDP password for this process only
        WINDOWSVM_PASSWORD_FILE  File containing the RDP password
        WINDOWSVM_BACKUP_DIR   Password-reset disk backups, default beside storage
        WINDOWSVM_LANGUAGE     Windows installation language
        WINDOWSVM_REGION       Windows installation region
        WINDOWSVM_KEYBOARD     Windows keyboard layout
        WINDOWSVM_RDP_CLIENT   FreeRDP client override (sdl-freerdp or xfreerdp)
        WINDOWSVM_RDP_DISPLAY_MODE  RDP size: half or fullscreen, default half
        WINDOWSVM_RDP_TIMEOUT  Seconds to wait for RDP from "up", default 90
        WINDOWSVM_RDP_ATTEMPTS RDP connection attempts from "up", default 10
        WINDOWSVM_PASSWORD_RESET_TIMEOUT  Seconds to verify the replacement, default 240
        WINDOWSVM_WIPE_CONFIRM  Must be exactly WIPE for the destructive wipe command
      USAGE
      }

      ensure_docker() {
        docker_error=$(mktemp)
        if ! docker info >/dev/null 2>"$docker_error"; then
          if reexec_with_docker_group; then
            exit 0
          fi

          cat "$docker_error" >&2
          rm -f "$docker_error"
          echo >&2
          echo "Docker is not reachable." >&2
          echo "Try: sudo systemctl start docker" >&2
          echo "If Docker works with sudo, restart your session so the docker group is applied." >&2
          exit 1
        fi
        rm -f "$docker_error"
      }

      load_password() {
        if [ -n "$password" ]; then
          return
        fi

        if [ -n "''${WINDOWSVM_PASSWORD_FILE:-}" ]; then
          if [ ! -f "$WINDOWSVM_PASSWORD_FILE" ]; then
            echo "WINDOWSVM_PASSWORD_FILE is not a readable regular file." >&2
            exit 1
          fi
          password=$(<"$WINDOWSVM_PASSWORD_FILE")
        elif [ -n "''${WINDOWSVM_PASSWORD:-}" ]; then
          password=$WINDOWSVM_PASSWORD
          unset WINDOWSVM_PASSWORD
        elif [ -t 0 ]; then
          printf 'Windows/RDP password: ' >&2
          IFS= read -r -s password
          printf '\n' >&2
        else
          echo "A Windows/RDP password is required." >&2
          echo "Set WINDOWSVM_PASSWORD_FILE (preferred), WINDOWSVM_PASSWORD, or run from a terminal." >&2
          exit 1
        fi

        if [ -z "$password" ]; then
          echo "The Windows/RDP password cannot be empty." >&2
          exit 1
        fi
        case "$password" in
          *$'\n'*|*$'\r'*)
            echo "The Windows/RDP password cannot contain newlines." >&2
            exit 1
            ;;
        esac
      }

      expected_image_fingerprint() {
        local config_path
        local config_hash
        local actual_config_hash
        local config_json

        if [ -z "$declared_image_file" ]; then
          echo "No declarative archive was found for $image." >&2
          return 1
        fi

        config_path=$(tar -xOf "$declared_image_file" manifest.json | jq -er '.[0].Config')
        config_hash=''${config_path%.json}
        if [[ ! "$config_hash" =~ ^[0-9a-f]{64}$ ]]; then
          echo "Invalid Docker config digest in $declared_image_file: $config_path" >&2
          return 1
        fi
        config_json=$(tar -xOf "$declared_image_file" "$config_path")
        actual_config_hash=$(printf '%s' "$config_json" | sha256sum | cut -d ' ' -f 1)
        if [ "$actual_config_hash" != "$config_hash" ]; then
          echo "Docker config payload does not match its digest in $declared_image_file." >&2
          return 1
        fi
        printf '%s' "$config_json" \
          | jq -ceS \
            '{architecture,os,created,config,rootfs:{type:.rootfs.type,diff_ids:.rootfs.diff_ids}}' \
          | sha256sum | cut -d ' ' -f 1
      }

      archive_image_ref() {
        local archive_ref

        if [ -z "$declared_image_file" ]; then
          echo "No declarative archive was found for $image." >&2
          return 1
        fi

        archive_ref=$(tar -xOf "$declared_image_file" manifest.json | jq -er '.[0].RepoTags[0]')
        archive_ref=''${archive_ref#docker.io/}
        archive_ref=''${archive_ref#index.docker.io/}
        printf '%s\n' "$archive_ref"
      }

      image_fingerprint() {
        local metadata

        metadata=$(docker image inspect "$1" 2>/dev/null || true)
        if [ -z "$metadata" ]; then
          return 0
        fi
        printf '%s' "$metadata" \
          | jq -ceS \
            '.[0] | {architecture:.Architecture,os:.Os,created:.Created,config:.Config,rootfs:{type:.RootFS.Type,diff_ids:.RootFS.Layers}}' \
          | sha256sum | cut -d ' ' -f 1
      }

      image_backend_identity() {
        docker image inspect "$1" \
          | jq -er '.[0] | (.Descriptor.digest // .Id)'
      }

      verify_image_identity() {
        local actual_fingerprint
        local expected_fingerprint

        expected_fingerprint=$(expected_image_fingerprint)
        actual_fingerprint=$(image_fingerprint "$image")
        if [ "$actual_fingerprint" != "$expected_fingerprint" ]; then
          echo "Docker image $image does not match its Nix-pinned archive." >&2
          echo "Expected fingerprint: $expected_fingerprint" >&2
          echo "Found fingerprint:    ''${actual_fingerprint:-missing}" >&2
          return 1
        fi
      }

      ensure_image() {
        local archive_fingerprint
        local archive_ref
        local expected_fingerprint

        if docker image inspect "$image" >/dev/null 2>&1; then
          verify_image_identity
          return
        fi

        if [ -n "$declared_image_file" ]; then
          expected_fingerprint=$(expected_image_fingerprint)
          archive_ref=$(archive_image_ref)
          archive_fingerprint=$(image_fingerprint "$archive_ref")
          echo "Loading Docker image $image from Nix store..."
          if [ "$archive_fingerprint" != "$expected_fingerprint" ]; then
            docker load --input "$declared_image_file"
            archive_fingerprint=$(image_fingerprint "$archive_ref")
          fi
          if [ "$archive_fingerprint" != "$expected_fingerprint" ]; then
            echo "The loaded Docker archive has an unexpected image identity." >&2
            echo "Expected fingerprint: $expected_fingerprint" >&2
            echo "Found fingerprint:    ''${archive_fingerprint:-missing}" >&2
            return 1
          fi
          docker tag "$archive_ref" "$image"
          verify_image_identity
          return
        fi

        echo "Docker image $image is not loaded and no declarative image file was found." >&2
        exit 1
      }

      check_devices() {
        if [ ! -e /dev/kvm ]; then
          echo "Missing /dev/kvm. Enable virtualization in BIOS/UEFI or check KVM support." >&2
          exit 1
        fi

        if [ ! -e /dev/net/tun ]; then
          echo "Missing /dev/net/tun. Rebuild first so the tun module is loaded." >&2
          exit 1
        fi
      }

      container_exists() {
        docker container inspect "$container_name" >/dev/null 2>&1
      }

      container_running() {
        [ "$(docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null || true)" = "true" ]
      }

      verify_container_image() {
        local actual_identity
        local expected_identity

        expected_identity=$(image_backend_identity "$image")
        actual_identity=$(docker container inspect "$container_name" \
          | jq -er '.[0] | (.ImageManifestDescriptor.digest // .Image)')
        if [ "$actual_identity" != "$expected_identity" ]; then
          echo "Container $container_name was created from a different image." >&2
          echo "Expected: $expected_identity" >&2
          echo "Found:    $actual_identity" >&2
          echo "Review its state, then recreate it with: windowsvm rm && windowsvm start" >&2
          exit 1
        fi
      }

      start_container() {
        ensure_docker
        ensure_image

        if container_exists; then
          verify_container_image
          if container_running; then
            echo "Container $container_name is already running."
          else
            echo "Starting existing container $container_name..."
            docker start "$container_name" >/dev/null
          fi
          return
        fi

        check_devices
        load_password
        mkdir -p "$storage_dir" "$shared_dir"

        echo "Creating container $container_name..."
        container_created=1
        if ! create_container; then
          container_created=0
          return 1
        fi

        echo "Storage: $storage_dir"
        echo "Shared:  $shared_dir"
      }

      create_container() (
        set -euo pipefail

        local container_environment
        local runtime_dir

        runtime_dir=''${XDG_RUNTIME_DIR:-/tmp}
        container_environment=$(mktemp "$runtime_dir/windowsvm-container-env.XXXXXX")
        chmod 600 "$container_environment"
        trap 'rm -f -- "$container_environment"' EXIT

        {
          printf 'VERSION=%s\n' "$version"
          printf 'CPU_CORES=%s\n' "$cpu_cores"
          printf 'RAM_SIZE=%s\n' "$ram_size"
          printf 'DISK_SIZE=%s\n' "$disk_size"
          printf 'USERNAME=%s\n' "$username"
          printf 'PASSWORD=%s\n' "$password"
          printf 'LANGUAGE=%s\n' "$language"
          printf 'REGION=%s\n' "$region"
          printf 'KEYBOARD=%s\n' "$keyboard"
        } > "$container_environment"

        docker run -d \
          --name "$container_name" \
          --env-file "$container_environment" \
          -p "$bind_address:$web_port:8006" \
          -p "$bind_address:$rdp_port:3389/tcp" \
          -p "$bind_address:$rdp_port:3389/udp" \
          --device=/dev/kvm \
          --device=/dev/net/tun \
          --cap-add NET_ADMIN \
          -v "$storage_dir:/storage" \
          -v "$shared_dir:/shared" \
          --stop-timeout 120 \
          "$image" >/dev/null
      )

      port_open() {
        timeout 1 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/$rdp_port" >/dev/null 2>&1
      }

      wait_for_rdp() {
        deadline=$((SECONDS + rdp_timeout))
        while [ "$SECONDS" -lt "$deadline" ]; do
          if port_open; then
            return 0
          fi
          sleep 3
        done

        return 1
      }

      select_rdp_client() {
        local requested
        requested=''${WINDOWSVM_RDP_CLIENT:-}

        if [ -n "$requested" ]; then
          case "$requested" in
            sdl-freerdp|xfreerdp)
              if command -v "$requested" >/dev/null 2>&1; then
                printf '%s\n' "$requested"
                return 0
              fi
              echo "Requested RDP client is not available: $requested" >&2
              return 1
              ;;
            *)
              echo "Unsupported WINDOWSVM_RDP_CLIENT: $requested" >&2
              echo "Use sdl-freerdp or xfreerdp." >&2
              return 1
              ;;
          esac
        fi

        if [ -n "''${WAYLAND_DISPLAY:-}" ]; then
          printf '%s\n' sdl-freerdp
          return 0
        fi

        if [ -n "''${DISPLAY:-}" ]; then
          printf '%s\n' xfreerdp
          return 0
        fi

        echo "No graphical Wayland or X11 session was detected." >&2
        echo "Open RDP from the desktop session, or use: windowsvm web" >&2
        return 1
      }

      normalize_rdp_display_mode() {
        case "$1" in
          half|fullscreen)
            printf '%s\n' "$1"
            ;;
          *)
            echo "Unsupported RDP display mode: $1" >&2
            echo "Use half or fullscreen." >&2
            return 1
            ;;
        esac
      }

      run_freerdp() {
        local rdp_client=$1
        local display_mode=$2
        local display_argument

        load_password
        case "$username" in
          *$'\n'*|*$'\r'*)
            echo "The Windows/RDP username cannot contain newlines." >&2
            return 1
            ;;
        esac

        case "$display_mode" in
          half)
            display_argument="/size:50%w"
            ;;
          fullscreen)
            display_argument="+f"
            ;;
          *)
            echo "Unsupported RDP display mode: $display_mode" >&2
            return 1
            ;;
        esac

        printf '%s\n' \
          "/v:127.0.0.1:$rdp_port" \
          "/u:$username" \
          "/p:$password" \
          "/cert:ignore" \
          "$display_argument" \
          "-decorations" \
          "+dynamic-resolution" \
          "/log-level:ERROR" \
          "/timeout:15000" \
          | "$rdp_client" /args-from:stdin
      }

      open_rdp() {
        local rdp_client
        local display_mode=$1

        ensure_docker

        if ! container_running; then
          echo "Container $container_name is not running. Use: windowsvm up" >&2
          exit 1
        fi

        rdp_client=$(select_rdp_client)
        run_freerdp "$rdp_client" "$display_mode"
      }

      open_rdp_with_retries() {
        local attempt
        local rdp_client
        local display_mode=$1

        rdp_client=$(select_rdp_client) || return 1
        attempt=1

        while [ "$attempt" -le "$rdp_attempts" ]; do
          echo "Opening RDP session ($attempt/$rdp_attempts)..."
          if run_freerdp "$rdp_client" "$display_mode"; then
            return 0
          fi

          attempt=$((attempt + 1))
          if [ "$attempt" -le "$rdp_attempts" ]; then
            echo "RDP disconnected while Windows was still getting ready; retrying in 5 seconds..."
            sleep 5
          fi
        done

        return 1
      }

      open_web() {
        local url="http://127.0.0.1:$web_port"

        if ! xdg-open "$url" >/dev/null 2>&1; then
          echo "Could not open the Windows web viewer." >&2
          echo "Open this URL manually: $url" >&2
          return 1
        fi
      }

      inject_password_reset() (
        set -euo pipefail

        local disk_path="$storage_dir/data.img"
        local encoded_command
        local firstboot_script
        local powershell_command
        local powershell_password
        local powershell_username
        local reset_dir
        local runtime_dir

        if [ ! -f "$disk_path" ]; then
          echo "The Windows system disk was not found: $disk_path" >&2
          return 1
        fi

        runtime_dir=''${XDG_RUNTIME_DIR:-/tmp}
        reset_dir=$(mktemp -d "$runtime_dir/windowsvm-password-reset.XXXXXX")
        chmod 700 "$reset_dir"
        trap 'rm -rf -- "$reset_dir"' EXIT

        powershell_username=''${username//\'/\'\'}
        powershell_password=''${password//\'/\'\'}
        powershell_command="\$ErrorActionPreference='Stop';\$user='$powershell_username';\$secure=ConvertTo-SecureString '$powershell_password' -AsPlainText -Force;Set-LocalUser -Name \$user -Password \$secure;Enable-LocalUser -Name \$user"
        encoded_command=$(printf '%s' "$powershell_command" \
          | iconv -f UTF-8 -t UTF-16LE \
          | base64 --wrap=0)
        unset powershell_command powershell_password password

        firstboot_script="$reset_dir/reset-password.bat"
        umask 077
        {
          printf '@echo off\n'
          printf 'powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand %s\n' "$encoded_command"
          printf 'if errorlevel 1 echo Holodeck password replacement failed. Review the Guestfs Firstboot log.\n'
          printf 'exit /b 0\n'
        } > "$firstboot_script"
        unset encoded_command

        echo "Scheduling a one-time Windows password replacement..."
        VIRT_TOOLS_DATA_DIR="$firstboot_tools_dir" virt-customize \
          --format raw \
          --add "$disk_path" \
          --no-logfile \
          --no-network \
          --firstboot "$firstboot_script"
      )

      create_password_reset_backup() {
        local backup_dir
        local backup_timestamp
        local disk_path="$storage_dir/data.img"

        backup_dir=''${WINDOWSVM_BACKUP_DIR:-''${storage_dir%/}-backups}
        backup_timestamp=$(date -u +%Y%m%dT%H%M%SZ)
        umask 077
        mkdir -p "$backup_dir"
        password_reset_backup=$(mktemp "$backup_dir/data-before-password-reset-$backup_timestamp.XXXXXX.img")

        echo "Creating a recoverable sparse copy before editing the Windows disk..."
        if ! cp --reflink=auto --sparse=always --preserve=timestamps \
          -- "$disk_path" "$password_reset_backup"; then
          rm -f -- "$password_reset_backup"
          echo "The disk backup could not be created; Windows was not modified." >&2
          return 1
        fi
        chmod 600 "$password_reset_backup"
        echo "Recovery copy: $password_reset_backup"
      }

      verify_password_reset() {
        local attempt=1
        local deadline=$((SECONDS + password_reset_timeout))
        local rdp_client

        rdp_client=$(select_rdp_client) || return 1
        echo "Waiting for Windows to apply and authenticate the replacement password..."
        while [ "$SECONDS" -lt "$deadline" ]; do
          if port_open; then
            echo "Checking the new credentials ($attempt)..."
            if printf '%s\n' \
              "/v:127.0.0.1:$rdp_port" \
              "/u:$username" \
              "/p:$password" \
              "/cert:ignore" \
              "+auth-only" \
              "/log-level:ERROR" \
              "/timeout:15000" \
              | "$rdp_client" /args-from:stdin; then
              return 0
            fi
            attempt=$((attempt + 1))
          fi
          sleep 5
        done
        return 1
      }

      validate_windows_credentials() {
        case "$username" in
          *[!A-Za-z0-9@!._-]*|"")
            echo "The Windows username may contain only letters, numbers, @, !, ., _ and -." >&2
            return 1
            ;;
        esac
        if [ "''${#username}" -gt 20 ]; then
          echo "A local Windows username cannot exceed 20 characters." >&2
          return 1
        fi
        if [ "''${#password}" -gt 127 ]; then
          echo "A local Windows password cannot exceed 127 characters." >&2
          return 1
        fi
      }

      validate_password_reset_credentials() {
        validate_windows_credentials
        if [[ ! "$password_reset_timeout" =~ ^[1-9][0-9]*$ ]]; then
          echo "WINDOWSVM_PASSWORD_RESET_TIMEOUT must be a positive number of seconds." >&2
          return 1
        fi
      }

      reset_password() {
        ensure_docker
        load_password
        validate_password_reset_credentials

        if ! container_exists; then
          echo "Container $container_name does not exist. Use 'windowsvm up' to create the VM with this password." >&2
          return 1
        fi
        if [ ! -f "$storage_dir/data.img" ]; then
          echo "The Windows system disk was not found: $storage_dir/data.img" >&2
          return 1
        fi

        if container_running; then
          echo "Stopping $container_name cleanly before editing its disk..."
          docker stop "$container_name" >/dev/null
        fi

        password_reset_backup=""
        if ! create_password_reset_backup; then
          echo "The stopped container was preserved and can be started again." >&2
          return 1
        fi

        if ! inject_password_reset; then
          echo "The password replacement could not be scheduled; the stopped container was preserved." >&2
          echo "Recovery copy: $password_reset_backup" >&2
          return 1
        fi

        echo "Recreating only the container metadata; Windows storage is preserved at $storage_dir."
        docker rm "$container_name" >/dev/null
        start_container
        echo "The new password will become active during this Windows boot."
        if verify_password_reset; then
          rm -f -- "$password_reset_backup"
          echo "The exact replacement password was accepted by Windows over RDP."
          echo "The temporary recovery copy was removed because validation succeeded."
          return 0
        fi

        echo "Windows did not accept the replacement password within ''${password_reset_timeout}s." >&2
        echo "The recovery copy was retained: $password_reset_backup" >&2
        echo "Review the VM in the web viewer before making another disk change." >&2
        return 1
      }

      validate_wipe_storage() {
        local current_uid
        local home_path
        local shared_path

        if [ "''${WINDOWSVM_WIPE_CONFIRM:-}" != "WIPE" ]; then
          echo "Refusing to wipe Windows without WINDOWSVM_WIPE_CONFIRM=WIPE." >&2
          return 1
        fi
        unset WINDOWSVM_WIPE_CONFIRM

        if [ -L "$storage_dir" ] || [ ! -d "$storage_dir" ]; then
          echo "The Windows storage must be an existing directory, not a symlink: $storage_dir" >&2
          return 1
        fi
        wipe_storage_path=$(realpath -e -- "$storage_dir")
        home_path=$(realpath -m -- "$HOME")
        shared_path=$(realpath -m -- "$shared_dir")
        case "$wipe_storage_path" in
          /|"$home_path"|"$shared_path"|/boot|/boot/*|/dev|/dev/*|/etc|/etc/*|/home|/nix|/nix/*|/proc|/proc/*|/run|/run/*|/sys|/sys/*|/usr|/usr/*|/var|/tmp)
            echo "Refusing to wipe an unsafe storage path: $wipe_storage_path" >&2
            return 1
            ;;
        esac

        current_uid=$(id -u)
        if [ "$(stat -c '%u' -- "$wipe_storage_path")" != "$current_uid" ]; then
          echo "The Windows storage is not owned by the current user: $wipe_storage_path" >&2
          return 1
        fi
        if [ ! -f "$wipe_storage_path/data.img" ] \
          || { [ ! -f "$wipe_storage_path/windows.ver" ] && [ ! -f "$wipe_storage_path/windows.mac" ]; }; then
          echo "The target does not look like Dockurr Windows storage: $wipe_storage_path" >&2
          return 1
        fi
      }

      wipe_windows_vm() {
        local wipe_quarantine
        local wipe_timestamp

        ensure_docker
        ensure_image
        check_devices
        load_password
        validate_windows_credentials
        validate_wipe_storage

        wipe_timestamp=$(date -u +%Y%m%dT%H%M%SZ)
        wipe_quarantine="$wipe_storage_path.wipe-$wipe_timestamp-$BASHPID"
        if [ -e "$wipe_quarantine" ]; then
          echo "Refusing to overwrite an existing wipe quarantine: $wipe_quarantine" >&2
          return 1
        fi

        echo "WIPE target: $wipe_storage_path"
        echo "The shared directory is preserved: $shared_dir"
        if container_exists; then
          if container_running; then
            echo "Stopping $container_name cleanly..."
            docker stop "$container_name" >/dev/null
          fi
          echo "Removing the old container metadata..."
          docker rm "$container_name" >/dev/null
        fi

        echo "Moving the old guest disk out of the active storage path..."
        mv -- "$wipe_storage_path" "$wipe_quarantine"
        if ! mkdir -- "$wipe_storage_path"; then
          mv -- "$wipe_quarantine" "$wipe_storage_path"
          echo "The old Windows storage was restored because fresh storage could not be created." >&2
          return 1
        fi
        storage_dir="$wipe_storage_path"

        echo "Creating a fresh Windows VM with the textbox credentials..."
        if ! start_container; then
          if container_exists; then
            docker rm -f "$container_name" >/dev/null 2>&1 || true
          fi
          rm -rf -- "$wipe_storage_path"
          mv -- "$wipe_quarantine" "$wipe_storage_path"
          echo "Fresh VM creation failed; the original Windows storage was restored." >&2
          return 1
        fi

        if ! rm -rf -- "$wipe_quarantine"; then
          echo "The fresh VM started, but the old guest storage could not be deleted: $wipe_quarantine" >&2
          return 1
        fi

        echo "WIPE complete. The old Windows guest disk was deleted."
        echo "A fresh installation is starting with user: $username"
        echo "Use the Web viewer to follow Windows Setup; RDP becomes available after installation."
        open_web || true
      }

      case "''${1:-help}" in
        up)
          rdp_display_mode=$(normalize_rdp_display_mode "''${2:-$rdp_display_mode}")
          start_container

          if [ "$container_created" = "1" ]; then
            echo "Fresh Windows VM created. Opening the web viewer for the initial setup."
            echo "When Windows reaches the desktop, run: windowsvm rdp"
            open_web
            exit 0
          fi

          echo "Waiting for RDP on 127.0.0.1:$rdp_port..."
          if wait_for_rdp; then
            if ! open_rdp_with_retries "$rdp_display_mode"; then
              echo "RDP is not accepting sessions yet. Opening the web viewer instead."
              open_web
            fi
          else
            echo "RDP is not ready yet. Opening the web viewer instead."
            open_web
          fi
          ;;
        start)
          start_container
          ;;
        rdp)
          rdp_display_mode=$(normalize_rdp_display_mode "''${2:-$rdp_display_mode}")
          open_rdp "$rdp_display_mode"
          ;;
        web)
          open_web
          ;;
        password-reset)
          reset_password
          ;;
        wipe)
          wipe_windows_vm
          ;;
        status)
          ensure_docker
          docker ps -a --filter "name=^/$container_name$" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
          ;;
        logs)
          ensure_docker
          docker logs -f "$container_name"
          ;;
        down|stop)
          ensure_docker
          if container_exists; then
            docker stop "$container_name"
          else
            echo "Container $container_name does not exist."
          fi
          ;;
        rm|remove)
          ensure_docker
          if container_exists; then
            docker rm -f "$container_name"
          else
            echo "Container $container_name does not exist."
          fi
          ;;
        help|-h|--help)
          usage
          ;;
        *)
          usage
          exit 1
          ;;
      esac
    '';
  };
in
{
  config =
    lib.mkIf
      (config.features.containers.enable && config.features.containers.engine == "docker" && vm.enable)
      {
        environment.systemPackages = [ windowsVmCommand ];
      };
}
