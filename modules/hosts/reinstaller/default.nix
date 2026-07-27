{
  config,
  lib,
  modulesPath,
  pkgs,
  holodeckSystemNixos,
  repoSource,
  ...
}:

let
  reinstallLauncher = pkgs.writeShellScript "holodeck-reinstall-launcher" ''
    set -euo pipefail

    encoded_disk=""
    for parameter in $(< /proc/cmdline); do
      case "$parameter" in
        holodeck.reinstallDisk64=*)
          encoded_disk="''${parameter#holodeck.reinstallDisk64=}"
          ;;
      esac
    done

    if [ -z "$encoded_disk" ]; then
      echo "Falta holodeck.reinstallDisk64 en la linea del kernel." >&2
      exit 1
    fi

    selected_disk="$(
      printf %s "$encoded_disk" \
        | ${lib.getExe' pkgs.coreutils "basenc"} --base64url -d
    )"
    case "$selected_disk" in
      /dev/disk/by-id/*) ;;
      *)
        echo "El parametro de disco no contiene un ID estable valido." >&2
        exit 1
        ;;
    esac

    echo "=============================================================="
    echo " Instalador efimero Holodeck: el sistema se ejecuta desde RAM"
    echo " Disco elegido previamente: $selected_disk"
    echo "=============================================================="
    echo
    echo "Se volvera a validar el disco y a pedir BORRAR antes de Disko."
    echo

    if ! ${lib.getExe' pkgs.networkmanager "nm-online"} \
      --quiet --timeout=15; then
      echo "No hay una conexion de red activa."
      echo "Configura Ethernet o Wi-Fi en NetworkManager para continuar."
      echo
      ${lib.getExe' pkgs.networkmanager "nmtui"}
      ${lib.getExe' pkgs.networkmanager "nm-online"} --quiet --timeout=30 \
        || {
          echo "No se obtuvo conectividad; no se modifico el disco." >&2
          exit 1
        }
    fi

    exec ${lib.getExe holodeckSystemNixos} \
      install \
      --target desktop \
      --repo ${lib.escapeShellArg (toString repoSource)} \
      --disk "$selected_disk"
  '';
in
{
  imports = [
    (modulesPath + "/installer/netboot/netboot-minimal.nix")
  ];

  networking.networkmanager.enable = lib.mkForce true;
  hardware.enableRedistributableFirmware = lib.mkForce true;
  boot.zfs.forceImportRoot = false;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  systemd.services.holodeck-reinstall = {
    description = "Holodeck destructive reinstall from RAM";
    wantedBy = [ "multi-user.target" ];
    wants = [ "NetworkManager.service" ];
    after = [
      "NetworkManager.service"
      "systemd-user-sessions.service"
    ];
    conflicts = [ "getty@tty1.service" ];
    before = [ "getty@tty1.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = reinstallLauncher;
      StandardInput = "tty-force";
      StandardOutput = "tty";
      StandardError = "tty";
      TTYPath = "/dev/tty1";
      TTYReset = true;
      TTYVHangup = true;
      TTYVTDisallocate = false;
    };
  };

  system.build.kexecScript = lib.mkForce (
    pkgs.writeShellScript "holodeck-kexec-boot" ''
      set -euo pipefail

      if [ "$#" -ne 1 ]; then
        echo "Uso: kexec-boot /dev/disk/by-id/ID" >&2
        exit 1
      fi
      selected_disk="$1"
      case "$selected_disk" in
        /dev/disk/by-id/*) ;;
        *)
          echo "Se requiere un ID estable de /dev/disk/by-id." >&2
          exit 1
          ;;
      esac

      encoded_disk="$(
        printf %s "$selected_disk" \
          | ${lib.getExe' pkgs.coreutils "basenc"} --base64url -w0
      )"
      script_dir="$(
        cd -- "$(dirname -- "''${BASH_SOURCE[0]}")"
        pwd
      )"

      ${lib.getExe' pkgs.kexec-tools "kexec"} --load "$script_dir/bzImage" \
        --initrd="$script_dir/initrd.gz" \
        --command-line \
          "init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams} holodeck.reinstallDisk64=$encoded_disk"
      ${lib.getExe' pkgs.coreutils "sync"}
      ${lib.getExe' pkgs.kexec-tools "kexec"} -e
    ''
  );

  netboot.squashfsCompression = "zstd -Xcompression-level 6";
  system.stateVersion = "26.05";
}
