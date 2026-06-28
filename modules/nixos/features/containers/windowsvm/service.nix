{ config, lib, pkgs, ... }:

let
  cfg = config.features.containers;
  vm = cfg.windowsVm;
in
{
  config = lib.mkIf (cfg.enable && cfg.engine == "docker" && vm.enable) {
    boot.kernelModules = [ "tun" ];
    environment.systemPackages = [ pkgs.freerdp ];
  };
}
