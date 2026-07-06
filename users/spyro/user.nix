{ ... }:
{
  spyroFlake.users.spyro = {
    groups = [
      "wheel"
      "networkmanager"
    ];
    system-modules = [ ./system ];
  };
}
