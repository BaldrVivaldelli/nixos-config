{
  lib,
  value ? null,
}:

let
  defaults = {
    schemaVersion = 2;

    deployment.target = "home-manager";

    desktop = {
      compositor = "niri";
      shell = "noctalia";
    };

    appearance.theme = {
      mode = "dark";
      builtin = "Catppuccin";
    };

    integrations.windows.rdp.displayMode = "half";
  };

  input = if value == null then defaults else value;
  inputVersion = if builtins.isAttrs input then input.schemaVersion or null else null;
  legacy = inputVersion == 1;
  ir =
    if legacy then
      lib.recursiveUpdate input {
        schemaVersion = 2;
        integrations.windows.rdp.displayMode = "half";
      }
    else
      input;
  exactKeys =
    expected: attrs:
    builtins.isAttrs attrs && lib.sort builtins.lessThan (builtins.attrNames attrs) == expected;
  expectedTopLevelKeys = [
    "appearance"
    "deployment"
    "desktop"
  ]
  ++ lib.optional (!legacy) "integrations"
  ++ [ "schemaVersion" ];
in
assert lib.assertMsg (builtins.isAttrs input) "Holodeck IR must be a JSON object";
assert lib.assertMsg (exactKeys expectedTopLevelKeys input)
  "Holodeck IR has unknown or missing top-level fields";
assert lib.assertMsg (builtins.elem inputVersion [
  1
  2
]) "unsupported Holodeck IR schemaVersion";
assert lib.assertMsg (
  ir.schemaVersion == 2
) "Holodeck IR migration did not produce schemaVersion 2";
assert lib.assertMsg (exactKeys [
  "target"
] ir.deployment) "Holodeck IR deployment must contain only target";
assert lib.assertMsg (builtins.elem ir.deployment.target [
  "home-manager"
  "existing-nixos"
]) "Holodeck IR deployment.target must be home-manager or existing-nixos";
assert lib.assertMsg (exactKeys [
  "compositor"
  "shell"
] ir.desktop) "Holodeck IR desktop must contain compositor and shell";
assert lib.assertMsg (
  ir.desktop.compositor == "niri"
) "Holodeck IR only supports the niri compositor";
assert lib.assertMsg (
  ir.desktop.shell == "noctalia"
) "Holodeck IR only supports the noctalia shell";
assert lib.assertMsg (exactKeys [
  "theme"
] ir.appearance) "Holodeck IR appearance must contain only theme";
assert lib.assertMsg (exactKeys [
  "builtin"
  "mode"
] ir.appearance.theme) "Holodeck IR appearance.theme must contain mode and builtin";
assert lib.assertMsg (builtins.elem ir.appearance.theme.mode [
  "dark"
  "light"
]) "Holodeck IR theme mode must be dark or light";
assert lib.assertMsg (
  builtins.isString ir.appearance.theme.builtin
  && ir.appearance.theme.builtin != ""
  && !(lib.hasInfix "\n" ir.appearance.theme.builtin)
  && !(lib.hasInfix "\r" ir.appearance.theme.builtin)
) "Holodeck IR builtin theme must be a non-empty single-line string";
assert lib.assertMsg (exactKeys [
  "windows"
] ir.integrations) "Holodeck IR integrations must contain only windows";
assert lib.assertMsg (exactKeys [
  "rdp"
] ir.integrations.windows) "Holodeck IR integrations.windows must contain only rdp";
assert lib.assertMsg (exactKeys [
  "displayMode"
] ir.integrations.windows.rdp) "Holodeck IR integrations.windows.rdp must contain only displayMode";
assert lib.assertMsg (builtins.elem ir.integrations.windows.rdp.displayMode [
  "half"
  "fullscreen"
]) "Holodeck IR Windows RDP display mode must be half or fullscreen";
ir
