{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.containers;
  defaultImages = builtins.fromJSON (builtins.readFile ./images.json);

  dockerImage =
    image:
    pkgs.dockerTools.pullImage (
      {
        inherit (image)
          imageName
          imageDigest
          hash
          finalImageTag
          os
          tlsVerify
          ;
        finalImageName = if image.finalImageName == null then image.imageName else image.finalImageName;
      }
      // lib.optionalAttrs (image.arch != null) {
        inherit (image) arch;
      }
    );

  dockerImages = map (image: rec {
    name = if image.finalImageName == null then image.imageName else image.finalImageName;
    archiveTag = image.finalImageTag;
    tag = if image.runtimeTag == null then archiveTag else image.runtimeTag;
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
      type = lib.types.enum [
        "podman"
        "docker"
      ];
      default = "docker";
      description = "Container runtime to enable when the containers feature is active.";
    };

    images = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
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

            runtimeTag = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Stable local tag used at runtime; defaults to finalImageTag.";
              example = "nixos-0123456789ab";
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
        }
      );
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

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
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
            archive_ref=$(${pkgs.gnutar}/bin/tar -xOf ${image.file} manifest.json \
              | ${pkgs.jq}/bin/jq -er '.[0].RepoTags[0]')
            archive_ref="''${archive_ref#docker.io/}"
            archive_ref="''${archive_ref#index.docker.io/}"
            config_path=$(${pkgs.gnutar}/bin/tar -xOf ${image.file} manifest.json \
              | ${pkgs.jq}/bin/jq -er '.[0].Config')
            config_hash="''${config_path%.json}"
            if [[ ! "$config_hash" =~ ^[0-9a-f]{64}$ ]]; then
              echo "Invalid Docker config digest in ${image.file}: $config_path" >&2
              exit 1
            fi
            config_json=$(${pkgs.gnutar}/bin/tar -xOf ${image.file} "$config_path")
            actual_config_hash=$(printf '%s' "$config_json" \
              | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.coreutils}/bin/cut -d ' ' -f 1)
            if [ "$actual_config_hash" != "$config_hash" ]; then
              echo "Docker config payload does not match its digest in ${image.file}" >&2
              exit 1
            fi

            expected_fingerprint=$(printf '%s' "$config_json" \
              | ${pkgs.jq}/bin/jq -ceS \
                '{architecture,os,created,config,rootfs:{type:.rootfs.type,diff_ids:.rootfs.diff_ids}}' \
              | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.coreutils}/bin/cut -d ' ' -f 1)

            image_fingerprint() {
              local metadata
              metadata=$(${config.virtualisation.docker.package}/bin/docker image inspect "$1" 2>/dev/null || true)
              if [ -z "$metadata" ]; then
                return 0
              fi
              printf '%s' "$metadata" \
                | ${pkgs.jq}/bin/jq -ceS \
                  '.[0] | {architecture:.Architecture,os:.Os,created:.Created,config:.Config,rootfs:{type:.RootFS.Type,diff_ids:.RootFS.Layers}}' \
                | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.coreutils}/bin/cut -d ' ' -f 1
            }

            loaded_fingerprint=$(image_fingerprint ${lib.escapeShellArg image.ref})

            if [ -f "$marker" ] \
              && [ "$(cat "$marker")" = ${lib.escapeShellArg image.storePath} ] \
              && [ "$loaded_fingerprint" = "$expected_fingerprint" ]; then
              echo "Docker image ${image.ref} already loaded"
            else
              echo "Loading Docker image ${image.ref}"
              archive_fingerprint=$(image_fingerprint "$archive_ref")
              if [ "$archive_fingerprint" != "$expected_fingerprint" ]; then
                ${config.virtualisation.docker.package}/bin/docker load --input ${image.file}
                archive_fingerprint=$(image_fingerprint "$archive_ref")
              fi
              if [ "$archive_fingerprint" != "$expected_fingerprint" ]; then
                echo "Docker archive ${image.file} loaded an unexpected image identity" >&2
                echo "Expected fingerprint: $expected_fingerprint" >&2
                echo "Found fingerprint:    ''${archive_fingerprint:-missing}" >&2
                exit 1
              fi
              ${config.virtualisation.docker.package}/bin/docker tag "$archive_ref" ${lib.escapeShellArg image.ref}
              loaded_fingerprint=$(image_fingerprint ${lib.escapeShellArg image.ref})
              if [ "$loaded_fingerprint" != "$expected_fingerprint" ]; then
                echo "Docker image ${image.ref} does not match its declared archive" >&2
                exit 1
              fi
              printf '%s\n' ${lib.escapeShellArg image.storePath} > "$marker"
            fi
          '') dockerImages;
        };
      })
    ]
  );
}
