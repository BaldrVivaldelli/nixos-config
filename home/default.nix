{
  inputs,
  user,
  ...
}:

let
  profileModules = {
    developer = ../modules/home/profiles/developer;
    minimal = ../modules/home/profiles/minimal;
  };
in
assert builtins.hasAttr user.homeProfile profileModules;
{
  imports = [
    inputs.noctalia.homeModules.default
    profileModules.${user.homeProfile}
  ];

  home = {
    username = user.username;
    homeDirectory = user.homeDirectory;
    stateVersion = "26.05";
  };

  homeFeatures.shell.repoPath = user.repoPath;

  programs.home-manager.enable = true;
  xdg.enable = true;
}
