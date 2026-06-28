{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-bak";
    users.avivaldelli = import ../../home/avivaldelli;
  };
}
