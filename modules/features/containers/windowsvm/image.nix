{ config, lib, pkgs, ... }:

let
  cfg = config.features.containers;
  vm = cfg.windowsVm;

  dockerImage = image:
    pkgs.dockerTools.pullImage ({
      inherit (image) imageName imageDigest hash finalImageTag os tlsVerify;
      finalImageName =
        if image.finalImageName == null
        then image.imageName
        else image.finalImageName;
    } // lib.optionalAttrs (image.arch != null) {
      inherit (image) arch;
    });

  dockerImages = map (image: rec {
    name =
      if image.finalImageName == null
      then image.imageName
      else image.finalImageName;
    tag = image.finalImageTag;
    ref = "${name}:${tag}";
    file = dockerImage image;
  }) cfg.images;

  windowsVmImageFiles = lib.filter (image: image.ref == vm.image) dockerImages;
in
{
  config.features.containers.windowsVm.imageFile =
    if windowsVmImageFiles == [ ]
    then ""
    else toString (lib.head windowsVmImageFiles).file;
}
