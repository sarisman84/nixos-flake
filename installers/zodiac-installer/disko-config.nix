# Disko configuration for the `zodiac` headless server install.
#
# Disk scheme: GPT + 512M EFI (vfat) + single btrfs root.
#
# The filesystem labels (`zodiac-boot`, `zodiac-root`) MUST match the device
# paths in `hosts/zodiac/hardware-configuration.nix`, which references the
# partitions by label (`/dev/disk/by-label/zodiac-root`,
# `/dev/disk/by-label/zodiac-boot`).  Without the labels the installed system
# hangs 90s on `/dev/disk/by-label/zodiac-root` and drops to emergency mode.
#
# `device` is `/dev/sda` for the QEMU install proof (the default drive
# interface).  For a bare-metal run, point it at the real disk
# (e.g. `/dev/nvme0n1`) before running disko.
#
# Usage (run on the installer ISO):
#   disko --mode destroy,format,mount --yes-wipe-all-disks /path/to/disko-config.nix

{
  disko.devices.disk.zodiac-disk = {
    device = "/dev/sda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        "zodiac-boot" = {
          type = "EF00";
          size = "512M";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            # Set the vfat volume label (mkfs.vfat -n).  Flag and value must be
            # separate list elements (see nix-community/disko#839).
            extraArgs = [ "-n" "zodiac-boot" ];
          };
        };
        "zodiac-root" = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "btrfs";
            mountpoint = "/";
            # Set the btrfs filesystem label (mkfs.btrfs -L).
            extraArgs = [ "-L" "zodiac-root" ];
          };
        };
      };
    };
  };
}
