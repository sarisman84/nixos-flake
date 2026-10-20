{pkgs, ...}:
{
  home = {
    packages = with pkgs; [
      bitwarden-desktop
      bws
      obs-studio
      vhs
      vlc
      filezilla
      postman
      ncdu
      dust
      proton-vpn
    ];
  };
}