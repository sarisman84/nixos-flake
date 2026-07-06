{ config, ... }:
let cfg = config.nixos.user;
in
{
  # cfg = {
  #   name = "Spyridon Passas";
  #   groups = [
  #     "wheel"
  #     "networkmanager"
  #   ];
  #   pkgsConfig = {
  #     permittedInsecurePackages = [
  #       "electron-39.8.10"
  #     ];
  #   };
  #   system.modules = [ ./system/default.nix ];
  # };

  name = "Spyridon Passas";
  groups = [
    "wheel"
    "networkmanager"
  ];
  pkgsConfig = {
    permittedInsecurePackages = [
      "electron-39.8.10"
    ];
  };
  system.modules = [ ./system/default.nix ];
}
