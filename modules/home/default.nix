{
  hostConfig,
  inputs,
  users,
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
      inherit inputs user;
    };
    users.${user.username} = import ../../home;
  };
}
