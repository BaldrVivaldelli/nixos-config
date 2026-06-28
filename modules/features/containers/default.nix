{ config, lib, pkgs, ... }:

let
  cfg = config.features.containers;
  defaultImages = builtins.fromJSON (builtins.readFile ./images.json);

  dockerImage = image:
    pkgs.dockerTools.pullImage ({
      inherit (image) imageName imageDigest hash finalImageTag os tlsVerify;
      finalImageName =
        if image.finalImageName == null
        then image.imageName
        else image.finalImageName;
    } // lib.optionalAttrs (image.arch != null) {
      inherit (image) arch;
    });

  dockerImages = map (image: rec {
    name =
      if image.finalImageName == null
      then image.imageName
      else image.finalImageName;
    tag = image.finalImageTag;
    ref = "${name}:${tag}";
    marker = builtins.replaceStrings [ "/" ":" "@" ] [ "-" "-" "-" ] ref;
    file = dockerImage image;
    storePath = toString file;
  }) cfg.images;

in
{
  imports = [
    ./service.nix
    ./windowsvm
  ];

  options.features.containers = {
    enable = lib.mkEnableOption "container runtime support";

    engine = lib.mkOption {
      type = lib.types.enum [ "podman" "docker" ];
      default = "docker";
      description = "Container runtime to enable when the containers feature is active.";
    };

    images = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          imageName = lib.mkOption {
            type = lib.types.str;
            description = "Source image name to fetch from the registry.";
            example = "docker.io/library/postgres";
          };

          imageDigest = lib.mkOption {
            type = lib.types.str;
            description = "Pinned OCI image digest.";
            example = "sha256:0000000000000000000000000000000000000000000000000000000000000000";
          };

          hash = lib.mkOption {
            type = lib.types.str;
            description = "Nix hash for the fetched Docker image archive.";
            example = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          };

          finalImageName = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Image name to store in Docker after loading. Defaults to imageName.";
            example = "postgres";
          };

          finalImageTag = lib.mkOption {
            type = lib.types.str;
            default = "latest";
            description = "Image tag to store in Docker after loading.";
            example = "16";
          };

          os = lib.mkOption {
            type = lib.types.str;
            default = "linux";
            description = "Image operating system to fetch.";
          };

          arch = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Image architecture to fetch. Defaults to the host platform architecture.";
            example = "amd64";
          };

          tlsVerify = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to verify TLS certificates when fetching the image.";
          };
        };
      });
      default = defaultImages;
      description = "Docker images to fetch with Nix and preload into Docker.";
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "alice" ];
      description = "Users allowed to control the selected container runtime.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf (cfg.engine == "podman") {
      virtualisation.podman.enable = true;
    })

    (lib.mkIf (cfg.engine == "docker") {
      virtualisation.docker.enable = true;
    })

    (lib.mkIf (cfg.engine == "docker" && dockerImages != [ ]) {
      systemd.services.docker-load-images = {
        description = "Load declarative Docker images";
        after = [ "docker.service" ];
        requires = [ "docker.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StateDirectory = "docker-load-images";
        };

        script = lib.concatMapStringsSep "\n" (image: ''
          marker=${lib.escapeShellArg "/var/lib/docker-load-images/${image.marker}"}

          if [ -f "$marker" ] \
            && [ "$(cat "$marker")" = ${lib.escapeShellArg image.storePath} ] \
            && ${config.virtualisation.docker.package}/bin/docker image inspect ${lib.escapeShellArg image.ref} >/dev/null 2>&1; then
            echo "Docker image ${image.ref} already loaded"
          else
            echo "Loading Docker image ${image.ref}"
            ${config.virtualisation.docker.package}/bin/docker load --input ${image.file}
            printf '%s\n' ${lib.escapeShellArg image.storePath} > "$marker"
          fi
        '') dockerImages;
      };
    })
  ]);
}
