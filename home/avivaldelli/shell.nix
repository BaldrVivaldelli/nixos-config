{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    eza
    fd
    jq
    ripgrep
  ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      size = 50000;
      save = 50000;
      path = "${config.xdg.dataHome}/zsh/history";
      ignoreDups = true;
      ignoreSpace = true;
      share = true;
    };

    shellAliases = {
      c = "clear";
      grep = "grep --color=auto";
      la = "eza -la --group-directories-first";
      ll = "eza -lh --group-directories-first";
      ls = "eza --group-directories-first";
      nixswitch = "sudo nixos-rebuild switch --flake ~/projects/personal/nixos-config#desktop";
      nixbuild = "sudo nixos-rebuild build --flake ~/projects/personal/nixos-config#desktop";
      rebuild = "nixswitch";
      ga = "git add";
      gc = "git commit";
      gd = "git diff";
      gs = "git status --short";
    };

    siteFunctions = {
      _windowsvm = ''
        #compdef windowsvm

        local -a commands
        commands=(
          'up:Start the Dockurr Windows container and open a client'
          'start:Start the container without opening a client'
          'rdp:Open FreeRDP against the running container'
          'web:Open the Dockurr web viewer'
          'status:Show the Docker container status'
          'logs:Follow container logs'
          'down:Stop the container'
          'stop:Stop the container'
          'rm:Stop and remove the container'
          'remove:Stop and remove the container'
          'help:Show help'
        )

        _arguments -C \
          '1:windowsvm command:->command' \
          '*::argument:->argument'

        case "$state" in
          command)
            _describe 'windowsvm command' commands
            ;;
        esac
      '';

      _holodeck = ''
        #compdef holodeck

        local -a commands providers
        commands=(
          'setup:Full wizard for GitHub personal and/or GitLab work'
          'github:Configure GitHub from your authenticated account'
          'gitlab:Configure one GitLab profile'
          'login:Authenticate a provider without configuring Git'
          'auth:Alias for login'
          'profile:Configure a provider profile'
          'doctor:Show profiles, auth state and key files'
          'status:Alias for doctor'
          'purge:Remove Holodeck-managed local profiles, keys and auth'
          'clean:Alias for purge'
          'sanitize:Alias for purge'
          'help:Show help'
        )
        providers=(
          'github:GitHub'
          'gitlab:GitLab'
        )

        _arguments -C \
          '1:holodeck command:->command' \
          '2:provider:->provider' \
          '*::argument:->argument'

        case "$state" in
          command)
            _describe 'holodeck command' commands
            ;;
          provider)
            case "$words[2]" in
              auth|login|profile)
                _describe 'provider' providers
                ;;
            esac
            ;;
        esac
      '';

      _aws_profiles = ''
        local -a profiles
        local profile

        while IFS= read -r profile; do
          [ -n "$profile" ] && profiles+=("$profile")
        done < <(aws configure list-profiles 2>/dev/null)

        if [ "''${#profiles[@]}" -eq 0 ]; then
          _message 'no AWS profiles found'
          return 1
        fi

        _describe 'AWS profile' profiles
      '';

      _awslogin = ''
        #compdef awslogin

        _aws_profiles
      '';

      _awscxt = ''
        #compdef awscxt

        _aws_profiles
      '';
    };

    initContent = lib.mkAfter ''
      setopt AUTO_CD
      setopt INTERACTIVE_COMMENTS
      setopt PUSHD_IGNORE_DUPS
    '';
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
