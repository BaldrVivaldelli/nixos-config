{ ... }:

{
  imports = [
    ../../features/desktop
  ];

  features.desktop = {
    enable = true;
    environment = "niri";
  };
}
