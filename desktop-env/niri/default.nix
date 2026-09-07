{ inputs, pkgs, ... }:
{
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  programs.niri.enable = true;
  programs.waybar.enable = true;

  # Required by Noctalia V5
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  # Installing Noctalia V5
  environment.systemPackages = [
    inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
