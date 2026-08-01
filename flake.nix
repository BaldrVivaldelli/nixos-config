{
  description = "Configuracion personal de Home Manager y NixOS-WSL";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
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
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      homeManagerCli = home-manager.packages.${system}.home-manager;
      homeProfile = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home/avivaldelli ];
      };
      holodeck = pkgs.callPackage ./packages/holodeck {
        coreSource = ./holodeck/core;
      };
      holodeck-system-nixos = pkgs.callPackage ./holodeck/backends/nixos/package.nix { };
      wsl = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
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

      homeConfigurations.avivaldelli = homeProfile;
      nixosConfigurations.wsl = wsl;

      checks.${system} = {
        home-profile =
          assert homeProfile.config.home.username == "avivaldelli";
          pkgs.runCommand "home-profile-check" { } ''
            touch "$out"
          '';

        wsl-profile =
          assert wsl.config.wsl.enable;
          assert wsl.config.wsl.defaultUser == "avivaldelli";
          pkgs.runCommand "wsl-profile-check" { } ''
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
