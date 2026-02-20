{ config, pkgs, ... }:
{
  programs.coolercontrol.enable = true;
  environment.systemPackages = with pkgs; [
    lm_sensors
    liquidctl
    linuxKernel.packages.linux_lqx.nct6687d
    mcontrolcenter
  ];

  services.hardware.openrgb.enable = true;
  boot.extraModulePackages = with config.boot.kernelPackages; [
    nct6687d
  ];
  boot.kernelModules = [ "ntc6775" ];

}
