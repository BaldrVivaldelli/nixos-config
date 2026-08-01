{
  inventory ? import ../inventory.nix,
  lib,
}:

let
  machine = inventory.machine or { };

  normalizeUser =
    userKey: user:
    let
      homeDirectory = user.homeDirectory or "/home/${user.username}";
      repoRelativePath = user.repoRelativePath or "projects/personal/nixos-config";
    in
    assert user ? username;
    user
    // {
      inherit userKey homeDirectory repoRelativePath;
      description = user.description or user.username;
      homeProfile = user.homeProfile or "developer";
      repoPath = user.repoPath or "${homeDirectory}/${repoRelativePath}";
    };

  users = lib.mapAttrs normalizeUser inventory.users;

  normalizeHost =
    hostKey: host:
    host
    // {
      hostName = host.hostName or machine.hostName or hostKey;
      timeZone = host.timeZone or machine.timeZone or "UTC";
    };

  hosts = lib.mapAttrs normalizeHost inventory.hosts;

  getHost = hostName: hosts.${hostName};
  getHostUser = hostName: users.${(getHost hostName).user};
in
assert builtins.hasAttr inventory.defaultHomeUser users;
{
  inherit
    inventory
    machine
    users
    hosts
    getHost
    getHostUser
    ;
  defaultHomeUser = users.${inventory.defaultHomeUser};
}
