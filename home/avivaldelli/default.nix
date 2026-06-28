{ ... }:

{
  imports = [
    ../../modules/home/features/shell
    ../../modules/home/features/starship
    ../../modules/home/features/aws
  ];

  home = {
    username = "avivaldelli";
    homeDirectory = "/home/avivaldelli";
    stateVersion = "26.05";
  };

  programs.home-manager.enable = true;
  xdg.enable = true;
}
