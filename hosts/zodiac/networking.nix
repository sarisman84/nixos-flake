{ config, pkgs, lib, ... }:

{
  # DNS resolution.
  services.resolved.enable = true;

  # NetworkManager (zodiac-admin is in the networkmanager group).
  networking.networkmanager.enable = true;

  networking.hostName = "zodiac"; # Define your hostname.
  networking.wireless.enable = lib.mkForce false; # No wireless on a headless server.

  # Open ports in the firewall — SSH only.
  # networking.firewall.allowedTCPPorts = [ 22 ];  # set in configuration.nix
}
