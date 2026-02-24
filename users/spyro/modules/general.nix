{pkgs, ...}:
{
  home = {
    packages = with pkgs; [
      bitwarden-desktop
      obs-studio
      vhs
      vlc
    ];
  };
}