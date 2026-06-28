# Changelog

All notable changes to this repository are documented here.

## 2026-06-28

### Added

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
- Linked system zsh completion paths with `environment.pathsToLink`.

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
