# Headless server configuration for `zodiac`.
#
# Base server only: SSH + firewall + sane defaults. No GUI, no desktop env.
# Disk scheme: GPT + EFI + single btrfs root with subvolumes (see disko config
# used by the installer ISO).  This file is installed from the flake via
# `nixos-install --flake <flake>#zodiac`.
#
# NOTE: ./hardware-configuration.nix is a placeholder.  It is regenerated during
# installation with `nixos-generate-config --root /mnt` after disko has
# partitioned and formatted the target disk.

{ sharedImports, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./locale.nix
    sharedImports.general
    sharedImports.nvidia
    sharedImports.garbage-collection
    ./networking.nix
  ];

  # Flatpak is enabled by sharedImports.general but not needed on a headless server.
  services.flatpak.enable = lib.mkForce false;

  # Bootloader — UEFI, systemd-boot.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # OpenSSH — key-only auth, root login prohibited without key.
  services.openssh.enable = true;
  services.openssh.settings = {
    PasswordAuthentication = false;
    PermitRootLogin = "prohibit-password";
    KbdInteractiveAuthentication = false;
  };

  # Firewall — enable, open SSH only.
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  # Editor + tools.
  environment.variables.EDITOR = "vim";

  # run0 (sudo alias) with session-cached auth.
  security = {
    sudo.enable = false;
    sudo-rs.enable = false;
    run0 = {
      enable = true;
      enableSudoAlias = true;
      wheelNeedsPassword = true;
      persistentAuth.enable = true;
    };
    polkit.settings.Polkitd.ExpirationSeconds = 1800;
  };

  # NixOS release version of the first install.
  system.stateVersion = "25.11";
}
