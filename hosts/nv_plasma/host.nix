{ ... }:
{
  spyroFlakes.hosts."two-b" = {
    system = "x86_64-linux";
    desktopEnv = "kde-plasma";
    users = [ "spyro" ];
    permittedInsecurePackages = [ "electron-39.8.10" ];
  };
}
