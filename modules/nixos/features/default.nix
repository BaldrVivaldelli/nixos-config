{ lib, ... }:

let
  entries = builtins.readDir ./.;

  featureModules = builtins.attrNames (
    lib.filterAttrs (
      name: type:
      (type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix")
      || (type == "directory" && builtins.pathExists (./. + "/${name}/default.nix"))
    ) entries
  );
in
{
  imports = map (name: ./. + "/${name}") featureModules;
}
