{ ... }:

{
  imports = [
    ./shell.nix
    ./starship.nix
    ./aws.nix
  ];

  home = {
    username = "avivaldelli";
    homeDirectory = "/home/avivaldelli";
    stateVersion = "26.05";
  };

  programs.home-manager.enable = true;
  xdg.enable = true;
}

