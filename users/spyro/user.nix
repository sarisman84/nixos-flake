{ ... }:
{
  spyroFlake.users.spyro = {
    groups = [
      "wheel"
      "networkmanager"
      "docker"
      # kwin_wayland does DRM atomic commits on /dev/dri/card* (root:video,
      # mode 660) to configure the display. Without video-group membership the
      # commit fails with "Permission denied" and the session lands on a black
      # screen after login.
      "video"
    ];
    system-modules = [ ./system ];
  };
}
