{ config, lib, pkgs, ... }:

let
  vm = config.features.containers.windowsVm;

  windowsVmCommand = pkgs.writeShellApplication {
    name = "windowsvm";
    runtimeInputs = [
      config.virtualisation.docker.package
      pkgs.bash
      pkgs.coreutils
      pkgs.freerdp
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
      default_password=$(printf '%s' ${lib.escapeShellArg vm.password})
      language=$(printf '%s' ${lib.escapeShellArg vm.language})
      region=$(printf '%s' ${lib.escapeShellArg vm.region})
      keyboard=$(printf '%s' ${lib.escapeShellArg vm.keyboard})
      web_port=${toString vm.webPort}
      rdp_port=${toString vm.rdpPort}
      declared_image_file=${lib.escapeShellArg vm.imageFile}

      storage_dir=''${WINDOWSVM_STORAGE:-$HOME/containers/windows/storage}
      shared_dir=''${WINDOWSVM_SHARED:-$HOME/containers/windows/shared}
      version=''${WINDOWSVM_VERSION:-$version}
      cpu_cores=''${WINDOWSVM_CPU_CORES:-$cpu_cores}
      ram_size=''${WINDOWSVM_RAM_SIZE:-$ram_size}
      disk_size=''${WINDOWSVM_DISK_SIZE:-$disk_size}
      username=''${WINDOWSVM_USER:-$default_username}
      password=''${WINDOWSVM_PASSWORD:-$default_password}
      language=''${WINDOWSVM_LANGUAGE:-$language}
      region=''${WINDOWSVM_REGION:-$region}
      keyboard=''${WINDOWSVM_KEYBOARD:-$keyboard}
      rdp_timeout=''${WINDOWSVM_RDP_TIMEOUT:-90}
      rdp_attempts=''${WINDOWSVM_RDP_ATTEMPTS:-10}
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
      Usage: windowsvm <command>

      Commands:
        up       Start the Dockurr Windows container
        start    Start the container without opening a client
        rdp      Open FreeRDP against the running container
        web      Open the Dockurr web viewer
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
        WINDOWSVM_PASSWORD     RDP password, default admin
        WINDOWSVM_LANGUAGE     Windows installation language
        WINDOWSVM_REGION       Windows installation region
        WINDOWSVM_KEYBOARD     Windows keyboard layout
        WINDOWSVM_RDP_TIMEOUT  Seconds to wait for RDP from "up", default 90
        WINDOWSVM_RDP_ATTEMPTS RDP connection attempts from "up", default 10
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

      ensure_image() {
        if docker image inspect "$image" >/dev/null 2>&1; then
          return
        fi

        if [ -n "$declared_image_file" ]; then
          echo "Loading Docker image $image from Nix store..."
          docker load --input "$declared_image_file"
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

      start_container() {
        ensure_docker
        ensure_image

        if container_exists; then
          if container_running; then
            echo "Container $container_name is already running."
          else
            echo "Starting existing container $container_name..."
            docker start "$container_name" >/dev/null
          fi
          return
        fi

        check_devices
        mkdir -p "$storage_dir" "$shared_dir"

        echo "Creating container $container_name..."
        container_created=1
        docker run -d \
          --name "$container_name" \
          -e "VERSION=$version" \
          -e "CPU_CORES=$cpu_cores" \
          -e "RAM_SIZE=$ram_size" \
          -e "DISK_SIZE=$disk_size" \
          -e "USERNAME=$username" \
          -e "PASSWORD=$password" \
          -e "LANGUAGE=$language" \
          -e "REGION=$region" \
          -e "KEYBOARD=$keyboard" \
          -p "$web_port:8006" \
          -p "$rdp_port:3389/tcp" \
          -p "$rdp_port:3389/udp" \
          --device=/dev/kvm \
          --device=/dev/net/tun \
          --cap-add NET_ADMIN \
          -v "$storage_dir:/storage" \
          -v "$shared_dir:/shared" \
          --stop-timeout 120 \
          "$image" >/dev/null

        echo "Storage: $storage_dir"
        echo "Shared:  $shared_dir"
      }

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

      run_xfreerdp() {
        printf '%s\n' \
          "/v:127.0.0.1:$rdp_port" \
          "/u:$username" \
          "/p:$password" \
          "/cert:ignore" \
          "/dynamic-resolution" \
          "/log-level:ERROR" \
          "/timeout:15000" \
          | xfreerdp /args-from:stdin
      }

      open_rdp() {
        ensure_docker

        if ! container_running; then
          echo "Container $container_name is not running. Use: windowsvm up" >&2
          exit 1
        fi

        run_xfreerdp
      }

      open_rdp_with_retries() {
        local attempt
        attempt=1

        while [ "$attempt" -le "$rdp_attempts" ]; do
          echo "Opening RDP session ($attempt/$rdp_attempts)..."
          if run_xfreerdp; then
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
        xdg-open "http://127.0.0.1:$web_port" >/dev/null 2>&1 &
      }

      case "''${1:-help}" in
        up)
          start_container

          if [ "$container_created" = "1" ]; then
            echo "Fresh Windows VM created. Opening the web viewer for the initial setup."
            echo "When Windows reaches the desktop, run: windowsvm rdp"
            open_web
            exit 0
          fi

          echo "Waiting for RDP on 127.0.0.1:$rdp_port..."
          if wait_for_rdp; then
            if ! open_rdp_with_retries; then
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
          open_rdp
          ;;
        web)
          open_web
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
  config = lib.mkIf (config.features.containers.enable && config.features.containers.engine == "docker" && vm.enable) {
    environment.systemPackages = [ windowsVmCommand ];
  };
}
