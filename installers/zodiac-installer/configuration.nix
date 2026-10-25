# Installer ISO configuration for `zodiac` headless server.
#
# Boots on the target machine, provides headless SSH access, and ships the
# tools needed for a non-interactive disko + nixos-install run:
#   disko-install --flake <flake>#zodiac --disk /dev/vda
#
# Built as: nix build .#nixosConfigurations.zodiac-installer.config.system.build.isoImage

{ pkgs, modulesPath, lib, ... }:

{
  imports = [
    # Minimal NixOS installer environment (bootable ISO base).
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # Headless SSH access — no console or keyboard needed.
  services.openssh.enable = true;
  services.openssh.settings = {
    PasswordAuthentication = false;
    PermitRootLogin = "prohibit-password";
    KbdInteractiveAuthentication = false;
  };

  # Initial root password for emergency/console access (QEMU proof uses this).
  users.users.root.initialPassword = "zodiac";

  # Nix flakes support for `nixos-install --flake ...` from the installer.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Tools needed for installation.
  environment.systemPackages = with pkgs; [ git ];

  # Filesystem support for the target disk (btrfs root, vfat EFI).
  boot.supportedFilesystems = lib.mkForce [ "btrfs" "vfat" "xfs" ];
}
