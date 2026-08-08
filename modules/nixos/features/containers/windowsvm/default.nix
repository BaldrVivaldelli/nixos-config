{ config, lib, ... }:

{
  imports = [
    ./image.nix
    ./commands.nix
    ./service.nix
  ];

  options.features.containers.windowsVm = {
    enable = lib.mkEnableOption "Dockurr Windows helper command";

    image = lib.mkOption {
      type = lib.types.str;
      default = "dockurr/windows:nixos-3633f055f31a";
      description = "Docker image reference used by the windowsvm command.";
    };

    imageFile = lib.mkOption {
      type = lib.types.str;
      default = "";
      internal = true;
      description = "Nix store path to the declared Docker image archive, if available.";
    };

    imageDigest = lib.mkOption {
      type = lib.types.str;
      default = "";
      internal = true;
      description = "Pinned registry digest for the declared Docker image.";
    };

    containerName = lib.mkOption {
      type = lib.types.str;
      default = "windows";
      description = "Docker container name used by the windowsvm command.";
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "11l";
      description = "Dockurr Windows VERSION value.";
    };

    cpuCores = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = "CPU cores assigned to the Windows VM.";
    };

    ramSize = lib.mkOption {
      type = lib.types.str;
      default = "4G";
      description = "RAM assigned to the Windows VM.";
    };

    diskSize = lib.mkOption {
      type = lib.types.str;
      default = "64G";
      description = "Disk size assigned to the Windows VM.";
    };

    username = lib.mkOption {
      type = lib.types.str;
      default = "Docker";
      description = "Default Windows user created during automatic installation.";
    };

    language = lib.mkOption {
      type = lib.types.str;
      default = "English";
      description = "Windows installation language.";
    };

    region = lib.mkOption {
      type = lib.types.str;
      default = "en-US";
      description = "Windows installation region.";
    };

    keyboard = lib.mkOption {
      type = lib.types.str;
      default = "en-US";
      description = "Windows keyboard layout.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host address used to expose the web viewer and RDP ports.";
    };

    allowRemoteAccess = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow publishing Windows VM ports on a non-loopback address.";
    };

    webPort = lib.mkOption {
      type = lib.types.port;
      default = 8006;
      description = "Host port for the Dockurr web viewer.";
    };

    rdpPort = lib.mkOption {
      type = lib.types.port;
      default = 3389;
      description = "Host port for RDP.";
    };

  };

  config.assertions = [
    {
      assertion =
        !config.features.containers.windowsVm.enable
        || config.features.containers.windowsVm.bindAddress == "127.0.0.1"
        || config.features.containers.windowsVm.allowRemoteAccess;
      message = ''
        A non-loopback Windows VM bindAddress requires
        features.containers.windowsVm.allowRemoteAccess = true.
      '';
    }
  ];
}
