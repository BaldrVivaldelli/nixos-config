{
  device ? "/dev/disk/by-id/SET_BY_INSTALL_DESKTOP",
  ...
}:

{
  disko.devices.disk.main = {
    inherit device;
    type = "disk";

    content = {
      type = "gpt";

      partitions = {
        ESP = {
          type = "EF00";
          size = "1G";

          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };

        cryptroot = {
          size = "100%";

          content = {
            type = "luks";
            name = "cryptroot";

            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
