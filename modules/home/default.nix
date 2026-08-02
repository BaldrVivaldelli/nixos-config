{
  hostConfig,
  inputs,
  users,
  holodeckIr,
  ...
}:

let
  user = users.${hostConfig.user};
in

{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-bak";
    extraSpecialArgs = {
      inherit inputs user holodeckIr;
    };
    users.${user.username} = import ../../home;
  };
}
