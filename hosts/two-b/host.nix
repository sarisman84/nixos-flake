{ ... }:
{
  spyroFlake.hosts.two-b = {
    system = "x86_64-linux";
    desktopEnv = "niri";
    users = [ "spyro" ];
    permittedInsecurePackages = [ "electron-39.8.10" ];
  };
}
