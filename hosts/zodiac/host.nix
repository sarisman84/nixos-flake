{ ... }:
{
  spyroFlake.hosts.zodiac = {
    system = "x86_64-linux";
    desktopEnv = "none";
    users = [ "zodiac-admin" ];
    permittedInsecurePackages = [ ];

    # Weekly automatic GC, keeping store generations ~10 months (see
    # shared/modules/garbage-collection.nix). Same as two-b.
    nixGC = {
      enable = true;
      dates = "weekly";
      deleteOlderThan = "300d";
    };
  };
}
