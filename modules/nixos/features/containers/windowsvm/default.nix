{ lib, ... }:

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
      default = "dockurr/windows:latest";
      description = "Docker image reference used by the windowsvm command.";
    };

    imageFile = lib.mkOption {
      type = lib.types.str;
      default = "";
      internal = true;
      description = "Nix store path to the declared Docker image archive, if available.";
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

    password = lib.mkOption {
      type = lib.types.str;
      default = "admin";
      description = "Default Windows password created during automatic installation.";
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
}
