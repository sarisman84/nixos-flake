{ ... }:
{
  spyroFlake.users.spyro = {
    groups = [
      "wheel"
      "networkmanager"
      "docker"
    ];
    system-modules = [ ./system ];
  };
}
