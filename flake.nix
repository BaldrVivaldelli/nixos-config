{
  description = "Configuracion personal exclusiva de Home Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
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
    in
    {
      packages.${system}.home-manager = homeManagerCli;

      apps.${system}.home-manager = {
        type = "app";
        program = "${homeManagerCli}/bin/home-manager";
        meta.description = "Aplicar la configuracion personal de Home Manager";
      };

      homeConfigurations.avivaldelli = homeProfile;

      checks.${system} = {
        home-profile =
          assert homeProfile.config.home.username == "avivaldelli";
          pkgs.runCommand "home-profile-check" { } ''
            touch "$out"
          '';

        user-only-policy = pkgs.runCommand "user-only-policy" {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.findutils
            pkgs.gnugrep
          ];
        } ''
          cd ${./.}
          bash ./verify-user-only.sh
          touch "$out"
        '';
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
