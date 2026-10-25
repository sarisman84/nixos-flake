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
  # Password auth enabled temporarily for QEMU install proof (#71).
  services.openssh.enable = true;
  services.openssh.settings = {
    PasswordAuthentication = true;
    PermitRootLogin = "yes";
    KbdInteractiveAuthentication = false;
  };

  # Initial root password + SSH key for QEMU install proof access.
  users.users.root.initialPassword = "zodiac";
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFnZeIOAInTihizsfXDayAdWGDJNWmJome3rtYEnO64u qemu-test"
  ];

  # Nix flakes support for `nixos-install --flake ...` from the installer.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Tools needed for installation.
  environment.systemPackages = with pkgs; [ git disko ];

  # Filesystem support for the target disk (btrfs root, vfat EFI).
  boot.supportedFilesystems = lib.mkForce [ "btrfs" "vfat" "xfs" ];
}
