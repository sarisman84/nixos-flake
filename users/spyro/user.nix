{ ... }:
{
  spyroFlakes.users."spyro" = {
    groups = [
      "wheel"
      "networkmanager"
    ];
    system = {
      pkgsConfig = {
        permittedInsecurePackages = [
          "electron-39.8.10"
        ];
        modules = [ ./system/default.nix ];
      };
    };
  };
}
