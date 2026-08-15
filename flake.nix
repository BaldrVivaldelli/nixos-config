{
  description = "Configuracion personal de Home Manager y NixOS-WSL";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia/v5.0.0-beta.7";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      home-manager,
      ...
    }:
    let
      lib = nixpkgs.lib;
      deployment = import ./lib/inventory.nix { inherit lib; };
      inherit (deployment) inventory users defaultHomeUser;
      holodeckIrPath = ./holodeck.local.json;
      holodeckIr = import ./lib/holodeck-ir.nix {
        inherit lib;
        value =
          if builtins.pathExists holodeckIrPath then
            builtins.fromJSON (builtins.readFile holodeckIrPath)
          else
            null;
      };
      defaultHolodeckIr = import ./lib/holodeck-ir.nix { inherit lib; };
      lightHolodeckIr = import ./lib/holodeck-ir.nix {
        inherit lib;
        value = lib.recursiveUpdate defaultHolodeckIr {
          appearance.theme.mode = "light";
        };
      };
      legacyHolodeckIr = import ./lib/holodeck-ir.nix {
        inherit lib;
        value = (builtins.removeAttrs defaultHolodeckIr [ "integrations" ]) // {
          schemaVersion = 1;
        };
      };
      invalidHolodeckIr = builtins.tryEval (
        import ./lib/holodeck-ir.nix {
          inherit lib;
          value = lib.recursiveUpdate defaultHolodeckIr {
            desktop.shell = "bash";
          };
        }
      );
      system = inventory.system or "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = package: lib.getName package == "kiro";
      };
      wslHost = deployment.getHost "wsl";
      wslUser = deployment.getHostUser "wsl";
      homeManagerCli = home-manager.packages.${system}.home-manager;
      mkHomeProfile =
        user:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = { inherit inputs user holodeckIr; };
          modules = [ ./home ];
        };
      homeProfiles = lib.mapAttrs (_userKey: mkHomeProfile) users;
      homeConfigurationsByUsername = builtins.listToAttrs (
        lib.mapAttrsToList (userKey: user: {
          name = user.username;
          value = homeProfiles.${userKey};
        }) users
      );
      homeProfile = homeProfiles.${inventory.defaultHomeUser};
      portableDeployment = import ./lib/inventory.nix {
        inherit lib;
        inventory = {
          defaultHomeUser = "test-user";
          users.test-user = {
            username = "portable-user";
            homeProfile = "minimal";
            repoRelativePath = "src/nixos-config";
          };
          hosts.test-host = {
            user = "test-user";
            hostName = "portable-host";
          };
        };
      };
      portableHomeProfile = mkHomeProfile portableDeployment.defaultHomeUser;
      portableHomeDirectory = "/home/${portableDeployment.defaultHomeUser.username}";
      niriProfile = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./modules/nixos/profiles/niri-desktop
          {
            boot.isContainer = true;
            system.stateVersion = "26.05";
          }
        ];
      };
      existingConfigurationPath = builtins.getEnv "NIXOS_EXISTING_CONFIGURATION";
      existingOverlayModules = [
        ./modules/nixos/features
        ./modules/nixos/profiles/niri-desktop
        {
          features.containers = {
            enable = true;
            engine = "docker";
            users = [ defaultHomeUser.username ];
            windowsVm.enable = true;
          };
        }
      ];
      existingTest = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {
            boot.isContainer = true;
            system.stateVersion = "26.05";
          }
        ]
        ++ existingOverlayModules;
      };
      existingTestWindowsVmPackage = lib.findFirst (
        package: lib.getName package == "windowsvm"
      ) (throw "existingTest must install windowsvm") existingTest.config.environment.systemPackages;
      insecureWindowsVmTest = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {
            boot.isContainer = true;
            system.stateVersion = "26.05";
          }
        ]
        ++ existingOverlayModules
        ++ [
          {
            features.containers.windowsVm.bindAddress = "0.0.0.0";
          }
        ];
      };
      insecureWindowsVmEvaluation = builtins.tryEval (
        builtins.deepSeq insecureWindowsVmTest.config.system.build.toplevel.drvPath true
      );
      existing =
        if existingConfigurationPath == "" then
          throw ''
            nixosConfigurations.existing requiere NIXOS_EXISTING_CONFIGURATION.
            Usá ./apply-nixos-system.sh o ./install.sh existing-nixos.
          ''
        else
          nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              (builtins.toPath existingConfigurationPath)
            ]
            ++ existingOverlayModules;
          };
      holodeck = pkgs.callPackage ./packages/holodeck {
        coreSource = ./holodeck/core;
      };
      holodeck-system-nixos = pkgs.callPackage ./holodeck/backends/nixos/package.nix {
        defaultWslUser = wslUser.username;
        defaultWslHostName = wslHost.hostName;
        defaultRepoPath = wslUser.repoPath;
      };
      holodeckctl = pkgs.callPackage ./packages/holodeckctl {
        inherit holodeck;
        defaultRepoPath = defaultHomeUser.repoPath;
      };
      noctaliaPlugin = pkgs.callPackage ./packages/holodeck-noctalia-plugin {
        noctalia = inputs.noctalia.packages.${system}.default;
        inherit holodeckctl;
      };
      wsl = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs users holodeckIr;
          hostConfig = wslHost;
        };
        modules = [
          inputs.nixos-wsl.nixosModules.default
          ./modules/parts.nix
          ./modules/hosts/wsl
        ];
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

      nixosModules.niri-desktop = import ./modules/nixos/profiles/niri-desktop;

      packages.${system} = {
        inherit
          holodeck
          holodeck-system-nixos
          ;
        home-manager = homeManagerCli;
        inherit holodeckctl;
        holodeck-noctalia-plugin = noctaliaPlugin;
      };

      apps.${system} = {
        home-manager = {
          type = "app";
          program = "${homeManagerCli}/bin/home-manager";
          meta.description = "Aplicar la configuracion personal de Home Manager";
        };

        holodeck = {
          type = "app";
          program = "${holodeck}/bin/holodeck";
          meta.description = "Configure portable developer identity and providers.";
        };

        holodeck-system-nixos = {
          type = "app";
          program = "${holodeck-system-nixos}/bin/holodeck-system-nixos";
          meta.description = "Install the declared NixOS-WSL target.";
        };

        holodeckctl = {
          type = "app";
          program = "${holodeckctl}/bin/holodeckctl";
          meta.description = "Manage the declarative Holodeck IR used by Noctalia and Nix.";
        };
      };

      homeConfigurations = homeConfigurationsByUsername // {
        default = homeProfile;
      };
      nixosConfigurations = {
        inherit wsl;
      }
      // lib.optionalAttrs (existingConfigurationPath != "") {
        inherit existing;
      };

      checks.${system} = {
        home-profile =
          assert builtins.hasAttr defaultHomeUser.username homeConfigurationsByUsername;
          assert homeProfile.config.home.username == defaultHomeUser.username;
          assert homeProfile.config.home.homeDirectory == defaultHomeUser.homeDirectory;
          assert homeProfile.config.home.sessionVariables.BROWSER == "chromium";
          assert homeProfile.config.home.sessionVariables.SHELL == "${pkgs.zsh}/bin/zsh";
          assert
            homeProfile.config.xdg.mimeApps.defaultApplications."x-scheme-handler/https"
            == [ "chromium-browser.desktop" ];
          assert homeProfile.config.programs.bash.enable;
          assert homeProfile.config.programs.zsh.enable;
          assert builtins.hasAttr "_windowsvm" homeProfile.config.programs.zsh.siteFunctions;
          assert builtins.hasAttr "_holodeck" homeProfile.config.programs.zsh.siteFunctions;
          assert homeProfile.config.homeFeatures.noctalia.enable;
          assert homeProfile.config.programs.noctalia.enable;
          assert !homeProfile.config.programs.noctalia.systemd.enable;
          assert
            homeProfile.config.programs.noctalia.settings.theme.builtin == holodeckIr.appearance.theme.builtin;
          assert homeProfile.config.programs.noctalia.settings.theme.mode == holodeckIr.appearance.theme.mode;
          assert
            homeProfile.config.programs.noctalia.settings.plugins.enabled == [
              "holodeck/control"
              "noctalia/wallhaven"
            ];
          assert
            homeProfile.config.programs.noctalia.settings.wallpaper.directory
            == "${defaultHomeUser.homeDirectory}/Pictures/Wallpaper";
          assert
            homeProfile.config.programs.noctalia.settings.wallpaper.default.path
            == "${defaultHomeUser.homeDirectory}/Pictures/Wallpaper/nave-wallpaper.png";
          assert
            homeProfile.config.programs.noctalia.settings.shell.launcher.providers == {
              calculator = {
                prefix = "calc";
                global = true;
              };
              emoji = {
                prefix = "emo";
                global = false;
              };
              session = {
                prefix = "session";
                global = false;
              };
              wallpaper = {
                prefix = "wall";
                global = false;
              };
              windows = {
                prefix = "win";
                global = false;
              };
            };
          assert builtins.elem "wallpaper" homeProfile.config.programs.noctalia.settings.bar.main.end;
          assert builtins.elem "noctalia/wallhaven:wallhaven"
            homeProfile.config.programs.noctalia.settings.bar.main.end;
          assert builtins.elem "holodeck/control:config"
            homeProfile.config.programs.noctalia.settings.bar.main.end;
          assert builtins.hasAttr "noctalia/plugins/holodeck-control" homeProfile.config.xdg.dataFile;
          assert builtins.hasAttr "holodeck-control" homeProfile.config.xdg.desktopEntries;
          assert lib.any (package: lib.getName package == "holodeckctl") homeProfile.config.home.packages;
          assert lib.any (
            package: lib.getName package == "holodeck-regenerate"
          ) homeProfile.config.home.packages;
          assert homeProfile.config.homeFeatures.niri.enable;
          assert homeProfile.config.home.sessionVariables.NIXOS_OZONE_WL == "1";
          assert homeProfile.config.programs.vscodium.enable;
          assert lib.any (package: lib.getName package == "kiro") homeProfile.config.home.packages;
          assert lib.any (package: lib.getName package == "detect-secrets") homeProfile.config.home.packages;
          assert
            homeProfile.config.programs.vscodium.profiles.default.userSettings == {
              "git.autofetch" = true;
              "workbench.colorTheme" = "Catppuccin Frappé";
              "workbench.iconTheme" = "catppuccin-mocha";
            };
          assert
            map (
              extension: extension.vscodeExtUniqueId
            ) homeProfile.config.programs.vscodium.profiles.default.extensions == [
              "catppuccin.catppuccin-vsc"
              "catppuccin.catppuccin-vsc-icons"
              "catppuccin.catppuccin-vsc-pack"
              "openai.chatgpt"
            ];
          pkgs.runCommand "home-profile-check" { } ''
            touch "$out"
          '';

        portable-home-profile =
          assert portableHomeProfile.config.home.username == "portable-user";
          assert portableHomeProfile.config.home.homeDirectory == portableHomeDirectory;
          assert
            portableHomeProfile.config.homeFeatures.shell.repoPath
            == "${portableHomeDirectory}/src/nixos-config";
          assert portableHomeProfile.config.homeFeatures.shell.enable;
          assert !(portableHomeProfile.config.homeFeatures ? noctalia);
          assert !(portableHomeProfile.config.homeFeatures ? niri);
          pkgs.runCommand "portable-home-profile-check" { } ''
            touch "$out"
          '';

        wsl-profile =
          assert wsl.config.wsl.enable;
          assert wsl.config.wsl.defaultUser == wslUser.username;
          assert wsl.config.networking.hostName == wslHost.hostName;
          assert wsl.config.time.timeZone == wslHost.timeZone;
          assert !wsl.config.home-manager.users.${wslUser.username}.homeFeatures.noctalia.enable;
          assert !wsl.config.home-manager.users.${wslUser.username}.programs.noctalia.enable;
          assert
            !(builtins.hasAttr "noctalia/plugins/holodeck-control"
              wsl.config.home-manager.users.${wslUser.username}.xdg.dataFile
            );
          assert !wsl.config.home-manager.users.${wslUser.username}.homeFeatures.niri.enable;
          assert !wsl.config.programs.niri.enable;
          assert !wsl.config.features.containers.enable;
          pkgs.runCommand "wsl-profile-check" { } ''
            touch "$out"
          '';

        niri-profile =
          assert niriProfile.config.programs.niri.enable;
          assert niriProfile.config.services.displayManager.sddm.enable;
          assert niriProfile.config.services.displayManager.defaultSession == "niri";
          assert builtins.elem "niri" niriProfile.config.services.displayManager.sessionData.sessionNames;
          assert !niriProfile.config.services.displayManager.autoLogin.enable;
          assert niriProfile.config.networking.networkmanager.enable;
          assert niriProfile.config.hardware.bluetooth.enable;
          assert niriProfile.config.services.upower.enable;
          assert niriProfile.config.services.power-profiles-daemon.enable;
          pkgs.runCommand "niri-profile-check" { } ''
            touch "$out"
          '';

        existing-test-profile =
          assert existingTest.config.programs.niri.enable;
          assert existingTest.config.services.displayManager.defaultSession == "niri";
          assert !existingTest.config.services.displayManager.autoLogin.enable;
          assert existingTest.config.features.containers.enable;
          assert existingTest.config.features.containers.engine == "docker";
          assert existingTest.config.features.containers.users == [ defaultHomeUser.username ];
          assert existingTest.config.features.containers.windowsVm.enable;
          assert existingTest.config.features.containers.windowsVm.bindAddress == "127.0.0.1";
          assert !existingTest.config.features.containers.windowsVm.allowRemoteAccess;
          assert !(existingTest.config.features.containers.windowsVm ? password);
          assert !lib.hasSuffix ":latest" existingTest.config.features.containers.windowsVm.image;
          assert existingTest.config.features.containers.windowsVm.imageFile != "";
          assert lib.hasPrefix "sha256:" existingTest.config.features.containers.windowsVm.imageDigest;
          assert existingTest.config.virtualisation.docker.enable;
          assert builtins.elem defaultHomeUser.username existingTest.config.users.groups.docker.members;
          assert !(existingTest.config.systemd.services ? docker-socket-user-access);
          assert lib.hasInfix "RepoTags[0]" existingTest.config.systemd.services.docker-load-images.script;
          assert lib.hasInfix "expected_fingerprint="
            existingTest.config.systemd.services.docker-load-images.script;
          assert lib.hasInfix "image_fingerprint()"
            existingTest.config.systemd.services.docker-load-images.script;
          assert lib.hasInfix "docker tag \"$archive_ref\""
            existingTest.config.systemd.services.docker-load-images.script;
          assert
            !lib.hasInfix "docker tag \"$expected_id\"" existingTest.config.systemd.services.docker-load-images.script;
          assert !insecureWindowsVmEvaluation.success;
          assert builtins.elem "tun" existingTest.config.boot.kernelModules;
          assert existingTestWindowsVmPackage != null;
          pkgs.runCommand "existing-test-profile-check" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
            grep -F 'unset WINDOWSVM_PASSWORD' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F '"+dynamic-resolution"' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F 'password-reset)' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F 'unlock)' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F 'IsAccountLocked=\$false' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F 'refusing automatic retries to avoid locking the account' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F '.windowsvm-credentials.json' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F 'must be owned by the current user with mode 600' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F 'Refusing to replace an unsafe Windows credential path' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F 'start_container 0' ${existingTestWindowsVmPackage}/bin/windowsvm
            test "$(grep -Fc 'load_password 0' ${existingTestWindowsVmPackage}/bin/windowsvm)" -eq 2
            grep -F 'flock --nonblock "$maintenance_lock_fd"' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F 'timeout --signal=TERM --kill-after=3s 20s' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F 'Authentication only, exit status SUCCESS' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F 'schemaVersion: 2' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F 'rdp_policy_version=1' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F 'net.exe accounts /lockoutthreshold:0' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F 'Holodeck will open RDP automatically when Windows is ready.' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F 'WINDOWSVM_INSTALL_TIMEOUT' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F 'repairing it automatically' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F 'wipe)' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F 'WINDOWSVM_WIPE_CONFIRM=WIPE' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F 'Refusing to wipe an unsafe storage path' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F 'VIRT_TOOLS_DATA_DIR="$firstboot_tools_dir" virt-customize' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F -- '--firstboot "$firstboot_script"' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F -- '--env-file "$container_environment"' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F '"+auth-only"' ${existingTestWindowsVmPackage}/bin/windowsvm
            grep -F 'cp --reflink=auto --sparse=always' ${existingTestWindowsVmPackage}/bin/windowsvm
            if grep -F -- '-e "PASSWORD=' ${existingTestWindowsVmPackage}/bin/windowsvm; then
              echo "windowsvm must not place the Windows password in Docker argv" >&2
              exit 1
            fi
            if grep -F 'docker image rm' ${existingTestWindowsVmPackage}/bin/windowsvm; then
              echo "windowsvm wipe must preserve the Nix-pinned runtime image" >&2
              exit 1
            fi
            if grep -F 'zenity' ${existingTestWindowsVmPackage}/bin/windowsvm; then
              echo "windowsvm must not open a second graphical password dialog" >&2
              exit 1
            fi
            if grep -F 'smart-sizing' ${existingTestWindowsVmPackage}/bin/windowsvm; then
              echo "windowsvm must not combine smart sizing with dynamic resolution" >&2
              exit 1
            fi
            touch "$out"
          '';

        holodeck-tests =
          pkgs.runCommand "holodeck-tests"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            }
            ''
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

        holodeckctl-tests =
          pkgs.runCommand "holodeckctl-tests"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            }
            ''
              cd ${./packages/holodeckctl}
              export PYTHONDONTWRITEBYTECODE=1
              export PYTHONPATH=src
              python3 -m unittest discover -s tests -v
              touch "$out"
            '';

        noctalia-plugin = noctaliaPlugin;

        holodeck-ir =
          assert defaultHolodeckIr.schemaVersion == 2;
          assert defaultHolodeckIr.deployment.target == "home-manager";
          assert defaultHolodeckIr.desktop.compositor == "niri";
          assert defaultHolodeckIr.desktop.shell == "noctalia";
          assert defaultHolodeckIr.integrations.windows.rdp.displayMode == "half";
          assert legacyHolodeckIr.schemaVersion == 2;
          assert legacyHolodeckIr.integrations.windows.rdp.displayMode == "half";
          assert lightHolodeckIr.appearance.theme.mode == "light";
          assert !invalidHolodeckIr.success;
          assert builtins.elem holodeckIr.appearance.theme.mode [
            "dark"
            "light"
          ];
          pkgs.runCommand "holodeck-ir-check" { } ''
            touch "$out"
          '';

        install-selector-tests =
          pkgs.runCommand "install-selector-tests"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.git
                pkgs.python3
              ];
            }
            ''
              cd ${./.}
              export PYTHONDONTWRITEBYTECODE=1
              python3 -m unittest discover -s holodeck/tests -v
              touch "$out"
            '';

        no-physical-desktop =
          pkgs.runCommand "no-physical-desktop"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.findutils
                pkgs.gnugrep
              ];
            }
            ''
              cd ${./.}
              bash ./verify-no-desktop.sh
              touch "$out"
            '';

        secret-scan =
          pkgs.runCommand "secret-scan"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.findutils
                pkgs.git
                pkgs.python3Packages.detect-secrets
              ];
            }
            ''
              cp -R ${./.} "$TMPDIR/source"
              chmod -R u+w "$TMPDIR/source"
              cd "$TMPDIR/source"
              git init --quiet
              git add --all

              if [ ! -x .githooks/pre-commit ]; then
                echo "Error: el hook pre-commit debe ser ejecutable." >&2
                exit 1
              fi
              bash -n .githooks/pre-commit

              find . -path ./.git -prune -o \
                -path ./.secrets.baseline -prune -o \
                -type f -printf '%P\0' \
                | xargs -0 detect-secrets-hook \
                    --baseline .secrets.baseline \
                    --no-verify

              self_test="$TMPDIR/detect-secrets-self-test"
              printf 'aws_access_key_id = %s%s\n' 'AKIA' 'Q7W4E9R2T6Y8U3I5' > "$self_test"
              if detect-secrets-hook --no-verify "$self_test" >/dev/null 2>&1; then
                echo "Error: el detector no reconoció la credencial sintética de control." >&2
                exit 1
              fi

              printf 'PASSWORD=%s\n' 'synthetic-local-value' > .env.local
              git add --force .env.local
              if .githooks/pre-commit >/dev/null 2>&1; then
                echo "Error: el hook no bloqueó un path sensible sintético." >&2
                exit 1
              fi

              touch "$out"
            '';
      };
    };
}
