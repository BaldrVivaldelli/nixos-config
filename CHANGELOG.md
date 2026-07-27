# Changelog

## 2026-07-27 - Safe rebuild storage profiles

### Fixed

- Restored the existing desktop's root, LUKS and EFI identifiers so a normal
  `#desktop` rebuild no longer generates an initrd for a different disk layout.
- Separated fresh Disko installations into `#desktop-disko`; the installer and
  the installed shell aliases keep using that profile after installation.
- Added flake assertions preventing the existing and Disko storage profiles
  from being mixed again.

## 2026-07-27 - Safe running-system reinstall

### Added

- Added the explicit `--allow-running-system-disk` desktop mode, requiring a
  manually selected `/dev/disk/by-id` disk and an extra exact confirmation.
- Added a NixOS kexec installer that runs from RAM before Disko touches the
  disk that held the previous running system.
- Added exclusion diagnostics that list detected disks, their protected
  mounts and the command for intentionally reinstalling the current system.
- Added tests for live installation, external targets, default root-disk
  rejection, advanced acceptance and failed-confirmation aborts.

### Changed

- Kept automatic disk discovery safe by default and separated it from manual
  selection and the destructive preflight revalidation.

## 2026-07-25 - Portable Holodeck system backends

### Added

- Added a single interactive and scriptable `install.sh` entrypoint.
- Added the optional `holodeck-system-nixos` backend with `desktop` and `wsl`
  targets.
- Added the `holodeck-system-<backend>` flake-app/executable contract for
  future operating-system integrations.
- Split core and backend tests into independent flake checks.

### Changed

- Moved the portable Python core to `holodeck/core`.
- Moved NixOS/Disko orchestration to `holodeck/backends/nixos`.
- Made the NixOS desktop backend detect safe stable disk candidates, preferring
  internal disks and prompting only when multiple candidates remain.
- Restored `./install-desktop.sh` as the zero-argument public entrypoint while
  keeping the NixOS backend as its internal implementation.
- Made the desktop backend automatically disable swap and unmount the confirmed
  target while protecting the live system disk.
- Made successful desktop installations sync and unmount `/mnt` automatically.
- Removed Nix, sudo and util-linux from the portable Holodeck runtime.
- Replaced `install-wsl.sh` and `bootstrap-wsl.sh` with the unified selector
  while keeping `install-desktop.sh` as the direct desktop entrypoint.

## 2026-07-25 - Unified Holodeck installation

### Added

- Added the flake app/package `holodeck` so it can run before the target system
  is installed.
- Added `holodeck system install` with `desktop` and `wsl` dispatch, shared
  preflight checks and unit tests.
- Added `install-wsl.sh` as the WSL counterpart to `install-desktop.sh`.

### Changed

- Reduced both installation scripts to thin wrappers around Holodeck.
- Kept `bootstrap-wsl.sh` as a compatibility alias for `install-wsl.sh`.
- Separated privileged system installation from `holodeck setup`; personal
  identity commands now reject execution as `root`.

## 2026-07-25 - Reproducible desktop installation

### Added

- Added Disko as a pinned flake input and NixOS module for `#desktop`.
- Added a declarative GPT, EFI, LUKS and ext4 layout.
- Added `install-desktop.sh` with UEFI, stable disk ID and destructive-action
  confirmation checks.

### Changed

- Removed installation-specific root, LUKS and EFI UUIDs from
  `hardware-configuration.nix`.
- Made `/boot` the explicit systemd-boot EFI mountpoint.
- Documented the destructive but reproducible fresh-install workflow.

## 2026-07-25 - NixOS-WSL host

### Added

- Added the `nixos-wsl` flake input pinned to the `release-26.05` branch.
- Added `nixosConfigurations.wsl` and `modules/hosts/wsl/default.nix`.
- Added Docker Desktop integration for WSL without enabling the native
  containers/Windows VM feature.
- Enabled `nix-ld` in WSL for VS Code Remote WSL compatibility.
- Added `bootstrap-wsl.sh`, `FIRST_RUN_WSL.md` and WSL documentation.

### Changed

- Parameterized Home Manager rebuild aliases so `desktop` targets `#desktop`
  and WSL targets `#wsl`.
- Reused Git, Python, Node.js, Lean, Holodeck and the developer Home Manager
  profile in WSL while omitting physical hardware, bootloader and desktop
  services.

All notable changes to this repository are documented here.

## 2026-06-28

### Added

- Added a `nixfmt` wrapper through `nix fmt` and a formatter dev shell.
- Added GitHub Actions CI for `nix flake check`.
- Added a minimal `features.browser` module for Chromium.
- Added `features.desktop` for GNOME, GDM and keyboard layout.
- Added `features.git` for Git, Git LFS, delta and lazygit.
- Added `features.lean` with `elan` as the default Lean toolchain manager.
- Added custom zsh completions for `windowsvm`, `holodeck`, `awslogin` and
  `awscxt` through Home Manager `siteFunctions`.
- Moved zsh completions into `modules/home/features/shell/completions.nix` and
  generate them from declarative Nix data.
- Moved reusable shell configuration into `modules/home/features/shell` so
  `home/avivaldelli` only references it.
- Moved NixOS features under `modules/nixos/features`.
- Moved Home Manager shell, starship and AWS modules under
  `modules/home/features`.
- Moved Home Manager wiring into `modules/home/default.nix` and import it from
  `modules/parts.nix`.
- Added Home Manager profiles and set `avivaldelli` to the `developer` profile.
- Converted Home Manager shell, starship and AWS modules to `homeFeatures.*`
  options.
- Added `features.graphics` with the Python `gpu-doctor` recommendation helper.
- Added interactive `gpu-doctor` apply flow for updating the host graphics
  config and running `nixos-rebuild`.
- Linked system zsh completion paths with `environment.pathsToLink`.

### Changed

- Split `features.desktop` into common options plus a dedicated `gnome.nix`
  implementation module.
- Moved Chromium setup from the `desktop` host into `features.browser`.
- Set Google as the default Chromium search provider in `features.browser`.
- Set Chromium as the default xdg handler for web links in `features.browser`.

### Documentation

- Documented custom zsh completions and how to refresh stale `.zcompdump`
  caches.

## 2026-06-28 - Home Manager workstation

### Added

- Added Home Manager as a flake input and integrated it into the `desktop`
  NixOS configuration.
- Added `home/avivaldelli/` for user-level configuration:
  - zsh shell setup with completion, autosuggestions, syntax highlighting and
    aliases.
  - fzf, zoxide and direnv integrations.
  - starship prompt configuration.
  - AWS CLI tooling with `awslogin`, `awscxt`, `awswho` and `awsprofiles`.
- Added a declarative Node.js feature under `features.nodejs`, including
  optional `pnpm` and `yarn` toggles.
- Added Home Manager and Node.js documentation.
- Added Python and Node.js local artifact patterns to `.gitignore`.

### Changed

- Set `zsh` as the default shell for user `avivaldelli`.
- Documented the boundary between NixOS system modules and Home Manager user
  configuration.
- Documented that Home Manager is applied through `nixos-rebuild` because it is
  integrated as a NixOS module.

## 2026-06-28 - Holodeck Python migration

### Added

- Reworked Holodeck into an internal Python project with a package layout.
- Added colored terminal output for Holodeck, respecting `NO_COLOR`.
- Added documentation for Holodeck's Python implementation and runtime wrapper.

### Changed

- Replaced the large Bash Holodeck script with a Python package executed via
  `python3 -m holodeck`.
- Updated the Nix wrapper to expose the internal Python package through
  `PYTHONPATH`.

## 2026-06-27

### Added

- Added the initial NixOS flake for the `desktop` host.
- Added modular features for VSCodium, Holodeck and containers.
- Added Docker image loading and Windows VM helper support.
