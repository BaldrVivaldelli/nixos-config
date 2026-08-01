{
  description = "Configuracion personal de Home Manager y NixOS-WSL";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia/v5.0.0-beta.7";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      home-manager,
      ...
    }:
    let
      lib = nixpkgs.lib;
      deployment = import ./lib/inventory.nix { inherit lib; };
      inherit (deployment) inventory users defaultHomeUser;
      system = inventory.system or "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      wslHost = deployment.getHost "wsl";
      wslUser = deployment.getHostUser "wsl";
      homeManagerCli = home-manager.packages.${system}.home-manager;
      mkHomeProfile =
        user:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit inputs user;
          };
          modules = [ ./home ];
        };
      homeProfiles = lib.mapAttrs (_userKey: mkHomeProfile) users;
      homeConfigurationsByUsername = builtins.listToAttrs (
        lib.mapAttrsToList (userKey: user: {
          name = user.username;
          value = homeProfiles.${userKey};
        }) users
      );
      homeProfile = homeProfiles.${inventory.defaultHomeUser};
      portableDeployment = import ./lib/inventory.nix {
        inherit lib;
        inventory = {
          defaultHomeUser = "test-user";
          users.test-user = {
            username = "portable-user";
            homeProfile = "minimal";
            repoRelativePath = "src/nixos-config";
          };
          hosts.test-host = {
            user = "test-user";
            hostName = "portable-host";
          };
        };
      };
      portableHomeProfile = mkHomeProfile portableDeployment.defaultHomeUser;
      portableHomeDirectory = "/home/${portableDeployment.defaultHomeUser.username}";
      niriProfile = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./modules/nixos/profiles/niri-desktop
          {
            boot.isContainer = true;
            system.stateVersion = "26.05";
          }
        ];
      };
      holodeck = pkgs.callPackage ./packages/holodeck {
        coreSource = ./holodeck/core;
      };
      holodeck-system-nixos = pkgs.callPackage ./holodeck/backends/nixos/package.nix {
        defaultWslUser = wslUser.username;
        defaultWslHostName = wslHost.hostName;
        defaultRepoPath = wslUser.repoPath;
      };
      wsl = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs users;
          hostConfig = wslHost;
        };
        modules = [
          inputs.nixos-wsl.nixosModules.default
          ./modules/parts.nix
          ./modules/hosts/wsl
        ];
      };
      formatter = pkgs.writeShellApplication {
        name = "nixfmt-tree";
        runtimeInputs = [
          pkgs.findutils
          pkgs.nixfmt
        ];
        text = ''
          if [ "$#" -gt 0 ]; then
            exec nixfmt "$@"
          fi

          while IFS= read -r -d "" file; do
            nixfmt "$file"
          done < <(
            find . \
              -path ./.git -prune -o \
              -type f \
              -name "*.nix" \
              -print0
          )
        '';
      };
    in
    {
      formatter.${system} = formatter;

      nixosModules.niri-desktop = import ./modules/nixos/profiles/niri-desktop;

      packages.${system} = {
        inherit holodeck holodeck-system-nixos;
        home-manager = homeManagerCli;
      };

      apps.${system} = {
        home-manager = {
          type = "app";
          program = "${homeManagerCli}/bin/home-manager";
          meta.description = "Aplicar la configuracion personal de Home Manager";
        };

        holodeck = {
          type = "app";
          program = "${holodeck}/bin/holodeck";
          meta.description = "Configure portable developer identity and providers.";
        };

        holodeck-system-nixos = {
          type = "app";
          program = "${holodeck-system-nixos}/bin/holodeck-system-nixos";
          meta.description = "Install the declared NixOS-WSL target.";
        };
      };

      homeConfigurations = homeConfigurationsByUsername // {
        default = homeProfile;
      };
      nixosConfigurations.wsl = wsl;

      checks.${system} = {
        home-profile =
          assert builtins.hasAttr defaultHomeUser.username homeConfigurationsByUsername;
          assert homeProfile.config.home.username == defaultHomeUser.username;
          assert homeProfile.config.home.homeDirectory == defaultHomeUser.homeDirectory;
          assert homeProfile.config.home.sessionVariables.BROWSER == "chromium";
          assert homeProfile.config.home.sessionVariables.SHELL == "${pkgs.zsh}/bin/zsh";
          assert
            homeProfile.config.xdg.mimeApps.defaultApplications."x-scheme-handler/https"
            == [ "chromium-browser.desktop" ];
          assert homeProfile.config.programs.bash.enable;
          assert homeProfile.config.programs.zsh.enable;
          assert homeProfile.config.homeFeatures.noctalia.enable;
          assert homeProfile.config.programs.noctalia.enable;
          assert !homeProfile.config.programs.noctalia.systemd.enable;
          assert homeProfile.config.programs.noctalia.settings.theme.builtin == "Catppuccin";
          assert homeProfile.config.homeFeatures.niri.enable;
          assert homeProfile.config.home.sessionVariables.NIXOS_OZONE_WL == "1";
          assert homeProfile.config.programs.vscodium.enable;
          assert
            homeProfile.config.programs.vscodium.profiles.default.userSettings == {
              "git.autofetch" = true;
              "workbench.colorTheme" = "Catppuccin Frappé";
              "workbench.iconTheme" = "catppuccin-mocha";
            };
          assert
            map (
              extension: extension.vscodeExtUniqueId
            ) homeProfile.config.programs.vscodium.profiles.default.extensions == [
              "catppuccin.catppuccin-vsc"
              "catppuccin.catppuccin-vsc-icons"
              "catppuccin.catppuccin-vsc-pack"
              "openai.chatgpt"
            ];
          pkgs.runCommand "home-profile-check" { } ''
            touch "$out"
          '';

        portable-home-profile =
          assert portableHomeProfile.config.home.username == "portable-user";
          assert portableHomeProfile.config.home.homeDirectory == portableHomeDirectory;
          assert
            portableHomeProfile.config.homeFeatures.shell.repoPath
            == "${portableHomeDirectory}/src/nixos-config";
          assert portableHomeProfile.config.homeFeatures.shell.enable;
          assert !(portableHomeProfile.config.homeFeatures ? noctalia);
          assert !(portableHomeProfile.config.homeFeatures ? niri);
          pkgs.runCommand "portable-home-profile-check" { } ''
            touch "$out"
          '';

        wsl-profile =
          assert wsl.config.wsl.enable;
          assert wsl.config.wsl.defaultUser == wslUser.username;
          assert wsl.config.networking.hostName == wslHost.hostName;
          assert wsl.config.time.timeZone == wslHost.timeZone;
          assert !wsl.config.home-manager.users.${wslUser.username}.homeFeatures.noctalia.enable;
          assert !wsl.config.home-manager.users.${wslUser.username}.programs.noctalia.enable;
          assert !wsl.config.home-manager.users.${wslUser.username}.homeFeatures.niri.enable;
          assert !wsl.config.programs.niri.enable;
          pkgs.runCommand "wsl-profile-check" { } ''
            touch "$out"
          '';

        niri-profile =
          assert niriProfile.config.programs.niri.enable;
          assert niriProfile.config.services.displayManager.sddm.enable;
          assert niriProfile.config.services.displayManager.defaultSession == "niri";
          assert builtins.elem "niri" niriProfile.config.services.displayManager.sessionData.sessionNames;
          assert !niriProfile.config.services.displayManager.autoLogin.enable;
          assert niriProfile.config.networking.networkmanager.enable;
          assert niriProfile.config.hardware.bluetooth.enable;
          assert niriProfile.config.services.upower.enable;
          assert niriProfile.config.services.power-profiles-daemon.enable;
          pkgs.runCommand "niri-profile-check" { } ''
            touch "$out"
          '';

        holodeck-tests =
          pkgs.runCommand "holodeck-tests"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            }
            ''
              cd ${./holodeck/core}
              export PYTHONDONTWRITEBYTECODE=1
              export PYTHONPATH=.
              python3 -m unittest discover -s tests -v
              touch "$out"
            '';

        holodeck-system-nixos-tests =
          pkgs.runCommand "holodeck-system-nixos-tests"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            }
            ''
              cd ${./holodeck/backends/nixos}
              export PYTHONDONTWRITEBYTECODE=1
              export PYTHONPATH=${./holodeck/core}:.
              python3 -m unittest discover -s tests -v
              touch "$out"
            '';

        install-selector-tests =
          pkgs.runCommand "install-selector-tests"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.python3
              ];
            }
            ''
              cd ${./.}
              export PYTHONDONTWRITEBYTECODE=1
              python3 -m unittest discover -s holodeck/tests -v
              touch "$out"
            '';

        no-physical-desktop =
          pkgs.runCommand "no-physical-desktop"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.findutils
                pkgs.gnugrep
              ];
            }
            ''
              cd ${./.}
              bash ./verify-no-desktop.sh
              touch "$out"
            '';
      };
    };
}
