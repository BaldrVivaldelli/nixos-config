{
  lib,
  value ? null,
}:

let
  defaults = {
    schemaVersion = 1;

    deployment.target = "home-manager";

    desktop = {
      compositor = "niri";
      shell = "noctalia";
    };

    appearance.theme = {
      mode = "dark";
      builtin = "Catppuccin";
    };
  };

  ir = if value == null then defaults else value;
  exactKeys =
    expected: attrs:
    builtins.isAttrs attrs && lib.sort builtins.lessThan (builtins.attrNames attrs) == expected;
in
assert lib.assertMsg (builtins.isAttrs ir) "Holodeck IR must be a JSON object";
assert lib.assertMsg (exactKeys [
  "appearance"
  "deployment"
  "desktop"
  "schemaVersion"
] ir) "Holodeck IR has unknown or missing top-level fields";
assert lib.assertMsg (ir.schemaVersion == 1) "unsupported Holodeck IR schemaVersion";
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
ir
