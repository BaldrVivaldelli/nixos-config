{
  hostConfig,
  lib,
  pkgs,
  users,
  ...
}:

let
  user = users.${hostConfig.user};
in

{
  # NixOS-WSL manages the kernel, initrd, bootloader, Windows mounts,
  # networking integration and WSL's systemd startup.
  wsl = {
    enable = true;
    defaultUser = user.username;

    # Use the Docker daemon supplied by Docker Desktop rather than starting
    # a second Docker daemon inside this distribution.
    docker-desktop.enable = true;
  };

  networking.hostName = hostConfig.hostName;

  time.timeZone = hostConfig.timeZone;

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "es_AR.UTF-8";
    LC_IDENTIFICATION = "es_AR.UTF-8";
    LC_MEASUREMENT = "es_AR.UTF-8";
    LC_MONETARY = "es_AR.UTF-8";
    LC_NAME = "es_AR.UTF-8";
    LC_NUMERIC = "es_AR.UTF-8";
    LC_PAPER = "es_AR.UTF-8";
    LC_TELEPHONE = "es_AR.UTF-8";
    LC_TIME = "es_AR.UTF-8";
  };

  # wsl.defaultUser defines the normal user and grants wheel access. These
  # extra properties define the interactive user environment.
  users.users.${user.username} = {
    description = user.description;
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  # VS Code Remote WSL downloads a non-Nix Node.js binary. nix-ld provides
  # the conventional dynamic loader path that this server expects.
  programs.nix-ld.enable = true;

  # Reuse the terminal/developer features available in this repository.
  features.git.enable = true;
  features.python.enable = true;
  features.nodejs.enable = true;
  features.lean.enable = true;
  features.holodeck.enable = true;

  # Keep graphical/user applications in the standalone Home Manager profile.
  home-manager.users.${user.username}.homeFeatures = {
    developerTools.enable = lib.mkForce false;
    noctalia.enable = lib.mkForce false;
    niri.enable = lib.mkForce false;
  };

  # Intentionally omitted in WSL:
  # - hardware-configuration.nix and physical bootloader settings
  # - NetworkManager, CUPS and PipeWire
  # - GNOME/GDM, Niri, Chromium, graphics drivers, Noctalia and VSCodium for Linux
  # - the native containers module and its dockurr/windows VM

  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.systemPackages = with pkgs; [
    wget
    curl
  ];

  environment.pathsToLink = [ "/share/zsh" ];

  system.stateVersion = "26.05";
}
