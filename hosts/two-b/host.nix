{ ... }:
{
  spyroFlake.hosts.two-b = {
    system = "x86_64-linux";
    desktopEnv = "kde-plasma";
    users = [ "spyro" ];
    permittedInsecurePackages = [ "electron-39.8.10" ];
    # Weekly automatic GC, keeping store generations ~10 months (see
    # shared/modules/garbage-collection.nix for the resulting NixOS options).
    nixGC = {
      enable = true;
      dates = "weekly";
      deleteOlderThan = "300d";
    };
  };
}
