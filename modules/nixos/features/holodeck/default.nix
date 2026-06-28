{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.holodeck;
in
{
  imports = [
    ./commands.nix
  ];

  options.features.holodeck = {
    enable = lib.mkEnableOption "interactive developer workstation setup";

    githubHost = lib.mkOption {
      type = lib.types.str;
      default = "github.com";
      description = "Default GitHub host used by holodeck.";
    };

    gitlabHost = lib.mkOption {
      type = lib.types.str;
      default = "gitlab.com";
      description = "Default GitLab host used by holodeck.";
    };

    personalProjectsDir = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/projects/personal";
      description = "Default directory for personal projects.";
    };

    workProjectsDir = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/projects/work";
      description = "Default directory for work projects.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      gh
      git
      glab
      gnupg
      openssh
    ];

    programs.gnupg.agent.enable = true;
  };
}
