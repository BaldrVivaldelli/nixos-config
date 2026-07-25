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
    inputs@{ nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      holodeck = pkgs.callPackage ./modules/nixos/features/holodeck/package.nix { };
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

      packages.${system}.holodeck = holodeck;

      apps.${system}.holodeck = {
        type = "app";
        program = "${holodeck}/bin/holodeck";
      };

      apps.${system}.disko = {
        type = "app";
        program = "${inputs.disko.packages.${system}.default}/bin/disko";
      };

      checks.${system}.holodeck-tests = pkgs.runCommand "holodeck-tests" {
        nativeBuildInputs = [ pkgs.python3 ];
      } ''
        cd ${./modules/nixos/features/holodeck/app}
        export PYTHONDONTWRITEBYTECODE=1
        export PYTHONPATH=.
        python3 -m unittest discover -s tests -v
        touch "$out"
      '';

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.findutils
          pkgs.nixfmt
        ];
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
