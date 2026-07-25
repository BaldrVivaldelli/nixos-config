{ pkgs, ... }:

{
  # NixOS-WSL manages the kernel, initrd, bootloader, Windows mounts,
  # networking integration and WSL's systemd startup.
  wsl = {
    enable = true;
    defaultUser = "avivaldelli";

    # Use the Docker daemon supplied by Docker Desktop rather than starting
    # a second Docker daemon inside this distribution.
    docker-desktop.enable = true;
  };

  networking.hostName = "nixos-wsl";

  time.timeZone = "America/Argentina/Buenos_Aires";

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
  # extra properties keep it aligned with the physical desktop host.
  users.users.avivaldelli = {
    description = "avivaldelli";
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  # VS Code Remote WSL downloads a non-Nix Node.js binary. nix-ld provides
  # the conventional dynamic loader path that this server expects.
  programs.nix-ld.enable = true;

  # Reuse the terminal/developer capabilities already enabled by #desktop.
  features.git.enable = true;
  features.python.enable = true;
  features.nodejs.enable = true;
  features.lean.enable = true;
  features.holodeck.enable = true;

  # Home Manager is imported globally by modules/parts.nix. Make its rebuild
  # aliases target this host instead of the physical desktop.
  home-manager.users.avivaldelli.homeFeatures.shell.rebuildTarget = "wsl";

  # Intentionally omitted in WSL:
  # - hardware-configuration.nix and physical bootloader settings
  # - NetworkManager, CUPS and PipeWire
  # - GNOME/GDM, Chromium, graphics drivers and VSCodium for Linux
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
