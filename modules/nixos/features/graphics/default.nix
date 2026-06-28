{ config, lib, pkgs, ... }:

let
  cfg = config.features.graphics;

  gpuDoctor = pkgs.writeShellApplication {
    name = "gpu-doctor";
    runtimeInputs = with pkgs; [
      pciutils
      python3
      git
    ];
    text = ''
      exec python3 ${./gpu-doctor.py} "$@"
    '';
  };
in
{
  options.features.graphics = {
    enable = lib.mkEnableOption "graphics acceleration and GPU diagnostics";

    driver = lib.mkOption {
      type = lib.types.enum [ "mesa" "amd" "intel" "nvidia" ];
      default = "mesa";
      description = ''
        Graphics driver family to configure.
        Use gpu-doctor to detect local GPUs and get a recommendation.
      '';
    };

    enable32Bit = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to enable 32-bit graphics libraries for Steam, Wine and older games.";
    };

    doctor.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install the gpu-doctor recommendation helper.";
    };

    nvidia = {
      open = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to use NVIDIA's open kernel module.
          Keep false for broad compatibility; try true for Turing or newer GPUs.
        '';
      };

      settings.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to install nvidia-settings.";
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = config.boot.kernelPackages.nvidiaPackages.stable;
        defaultText = lib.literalExpression "config.boot.kernelPackages.nvidiaPackages.stable";
        description = "NVIDIA driver package to use.";
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      hardware.graphics = {
        enable = true;
        enable32Bit = cfg.enable32Bit;
      };

      environment.systemPackages = lib.optional cfg.doctor.enable gpuDoctor;
    }

    (lib.mkIf (cfg.driver == "amd") {
      services.xserver.videoDrivers = [ "amdgpu" ];
    })

    (lib.mkIf (cfg.driver == "intel") {
      services.xserver.videoDrivers = [ "modesetting" ];
    })

    (lib.mkIf (cfg.driver == "nvidia") {
      services.xserver.videoDrivers = [ "nvidia" ];

      hardware.nvidia = {
        modesetting.enable = true;
        open = cfg.nvidia.open;
        nvidiaSettings = cfg.nvidia.settings.enable;
        package = cfg.nvidia.package;
      };
    })
  ]);
}
