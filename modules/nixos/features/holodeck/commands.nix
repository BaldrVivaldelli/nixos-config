{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.holodeck;

  holodeckCommand = pkgs.callPackage ./package.nix {
    inherit (cfg)
      githubHost
      gitlabHost
      personalProjectsDir
      workProjectsDir
      ;
  };
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ holodeckCommand ];
  };
}
