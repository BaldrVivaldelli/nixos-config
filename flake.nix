{
  description = "Mi configuración NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      holodeck = pkgs.callPackage ./modules/nixos/features/holodeck/package.nix { };
      holodeck-system-nixos = pkgs.callPackage ./holodeck/backends/nixos/package.nix { };
      reinstaller = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          holodeckSystemNixos = holodeck-system-nixos;
          repoSource = self;
        };
        modules = [ ./modules/hosts/reinstaller ];
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
        reinstaller-kexec = reinstaller.config.system.build.kexecTree;
      };

      apps.${system} = {
        holodeck = {
          type = "app";
          program = "${holodeck}/bin/holodeck";
          meta.description = "Configure portable developer identity and providers.";
        };

        holodeck-system-nixos = {
          type = "app";
          program = "${holodeck-system-nixos}/bin/holodeck-system-nixos";
          meta.description = "Install the declared NixOS desktop or WSL target.";
        };

        disko = {
          type = "app";
          program = "${inputs.disko.packages.${system}.default}/bin/disko";
          meta.description = "Apply the declarative NixOS desktop disk layout.";
        };
      };

      checks.${system} = {
        holodeck-tests = pkgs.runCommand "holodeck-tests" {
          nativeBuildInputs = [ pkgs.python3 ];
        } ''
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

        install-selector-tests = pkgs.runCommand "install-selector-tests" {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.python3
          ];
        } ''
          cd ${./.}
          export PYTHONDONTWRITEBYTECODE=1
          python3 -m unittest discover -s holodeck/tests -v
          touch "$out"
        '';
      };

      devShells.${system} = {
        default = pkgs.mkShell {
          packages = [
            pkgs.findutils
            pkgs.nixfmt
          ];
        };
      };

      nixosConfigurations.desktop = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
        };

        modules = [
          inputs.disko.nixosModules.disko
          ./modules/parts.nix
          ./modules/hosts/desktop
        ];
      };

      nixosConfigurations.reinstaller = reinstaller;

      nixosConfigurations.wsl = nixpkgs.lib.nixosSystem {
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
    };
}
