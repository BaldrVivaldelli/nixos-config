{ config, lib, pkgs, ... }:

let
  cfg = config.features.containers;
  dockerSocketAclCommands =
    lib.concatMapStringsSep "\n"
      (user: "setfacl -m ${lib.escapeShellArg "u:${user}:rw"} /run/docker.sock")
      cfg.users;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf (cfg.engine == "docker" && cfg.users != [ ]) {
      users.groups.docker.members = cfg.users;

      systemd.services.docker-socket-user-access = {
        description = "Grant configured users access to the Docker socket";
        after = [ "docker.socket" ];
        requires = [ "docker.socket" ];
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.acl ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = dockerSocketAclCommands;
      };
    })

    (lib.mkIf (cfg.engine == "podman" && cfg.users != [ ]) {
      users.groups.podman.members = cfg.users;
    })
  ]);
}
