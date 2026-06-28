{ ... }:

{
  imports = [
    ../../modules/home/profiles/developer
  ];

  home = {
    username = "avivaldelli";
    homeDirectory = "/home/avivaldelli";
    stateVersion = "26.05";
  };

  programs.home-manager.enable = true;
  xdg.enable = true;
}
