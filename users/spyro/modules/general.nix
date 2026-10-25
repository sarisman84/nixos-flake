{pkgs, ...}:
{
  home = {
    packages = with pkgs; [
      bitwarden-desktop
      obs-studio
      qemu_full
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