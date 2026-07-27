# Hardware detected by `nixos-generate-config`.
# Storage is selected separately by the flake configuration so that a normal
# rebuild cannot silently replace the active system's filesystem declarations
# with the destructive installer's layout.
{
  config,
  lib,
  modulesPath,
  useCurrentStorage ? true,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  config = lib.mkMerge [
    {
      boot.initrd.availableKernelModules = [
        "nvme"
        "xhci_pci"
        "usb_storage"
        "usbhid"
        "sd_mod"
      ];
      boot.initrd.kernelModules = [ ];
      boot.kernelModules = [ "kvm-amd" ];
      boot.extraModulePackages = [ ];

      swapDevices = [ ];

      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
      hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    }

    # `desktop` describes the layout that already exists on this machine.
    # `desktop-disko` disables this block and gets its storage from disko.nix.
    (lib.mkIf useCurrentStorage {
      fileSystems."/" = {
        device = "/dev/mapper/luks-7bc1af0e-bc6b-401e-81fa-57a07cb9e7f6";
        fsType = "ext4";
      };

      boot.initrd.luks.devices."luks-7bc1af0e-bc6b-401e-81fa-57a07cb9e7f6".device =
        "/dev/disk/by-uuid/7bc1af0e-bc6b-401e-81fa-57a07cb9e7f6";

      fileSystems."/boot" = {
        device = "/dev/disk/by-uuid/F844-5814";
        fsType = "vfat";
        options = [
          "fmask=0077"
          "dmask=0077"
        ];
      };
    })
  ];
}
