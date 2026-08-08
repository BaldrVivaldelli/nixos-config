{
  config,
  lib,
  ...
}:

let
  cfg = config.features.containers;
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.engine == "docker" && cfg.users != [ ]) {
        users.groups.docker.members = cfg.users;
      })

      (lib.mkIf (cfg.engine == "podman" && cfg.users != [ ]) {
        users.groups.podman.members = cfg.users;
      })
    ]
  );
}
