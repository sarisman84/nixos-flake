{ pkgs, ... }:
{
  home = {
    packages = with pkgs; [
      penpot-desktop
      pnpm
    ];
  };

}
