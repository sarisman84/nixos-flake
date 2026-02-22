{ pkgs, ... }:
{
  #programs.fancontrol.enable = true;
  environment.systemPackages = with pkgs; [
    lm_sensors
    liquidctl
  ];

  services.hardware.openrgb.enable = true;
  boot.kernelModules = [ "ntc6683" ];

}
