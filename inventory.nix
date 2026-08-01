let
  defaults = {
    system = "x86_64-linux";
    defaultHomeUser = "personal";

    machine = {
      os = "nixos";
      architecture = "x86_64";
      hostName = "nixos-wsl";
      timeZone = "America/Argentina/Buenos_Aires";
      isWsl = true;
    };

    users.personal = {
      username = "avivaldelli";
      homeProfile = "developer";
      repoRelativePath = "projects/personal/nixos-config";
    };

    hosts.wsl.user = "personal";
  };

  localInventoryPath = ./inventory.local.nix;
  localInventory = if builtins.pathExists localInventoryPath then import localInventoryPath else { };

  recursiveUpdate =
    lhs: rhs:
    lhs
    // builtins.mapAttrs (
      name: rhsValue:
      let
        lhsValue = lhs.${name} or null;
      in
      if builtins.isAttrs lhsValue && builtins.isAttrs rhsValue then
        recursiveUpdate lhsValue rhsValue
      else
        rhsValue
    ) rhs;
in
recursiveUpdate defaults localInventory
