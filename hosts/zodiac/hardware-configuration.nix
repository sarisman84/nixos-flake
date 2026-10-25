# Placeholder hardware configuration for `zodiac`.
#
# This file is regenerated during installation with:
#   nixos-generate-config --root /mnt
#
# after disko has partitioned and formatted the target disk (GPT + EFI +
# single btrfs root).  Replace this placeholder with the generated file at that
# time.  The values below match the expected disk scheme (1 disk, EFI + btrfs
# root) but the device paths are placeholders and must be corrected at install.

{ config, lib, pkgs, ... }:

{
  boot.initrd.availableKernelModules = [ "xhci_pci" "usbhid" "usb_storage" "sd_mod" "nvme" "btrfs" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  fileSystems."/" = {
    device = "/dev/disk/by-label/zodiac-root";
    fsType = "btrfs";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/zodiac-boot";
    fsType = "vfat";
  };
  swapDevices = [ ];
}
