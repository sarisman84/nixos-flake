# { config, ... }:
# let
#   cfg = config.nixos.machine;
# in
{
  # cfg = {
  #   system = "x86_64-linux";
  #   desktopEnv = "kde-plasma";
  #   users = [ "spyro" ];
  # };
  
  system = "x86_64-linux";
  desktopEnv = "kde-plasma";
  users = [ "spyro" ];
}
