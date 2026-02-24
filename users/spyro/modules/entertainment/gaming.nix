{ pkgs, flake-inputs, ... }:
{
  imports = [
    flake-inputs.nix-flatpak.homeManagerModules.nix-flatpak
  ];
  programs = {
    lutris.enable = true;
  };

  home = {
    packages = with pkgs; [
      #moonlight-qt
      (callPackage ./moonlight-qt-patched.nix { inherit pkgs; })
      steam
      wineWow64Packages.stable
      winetricks
      rusty-path-of-building
      (callPackage ./moonlight-qt-patched.nix { inherit pkgs; })
    ];
  };
}
