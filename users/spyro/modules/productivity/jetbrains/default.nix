{ pkgs, lib, flake-inputs, ... }:
let
  ext = import ./patched_jetbrains_rider.nix { inherit pkgs; inherit lib; };
in
{
  imports = [
    flake-inputs.nix-flatpak.homeManagerModules.nix-flatpak
  ];

  home = {
    packages = with pkgs;[
      jetbrains-toolbox
      ext.rider
    ];
  };

  home.file = {
  ".local/share/applications/jetbrains-rider.desktop".source =
      let
        desktopFile = pkgs.makeDesktopItem {
          name = "jetbrains-rider";
          desktopName = "Rider";
          exec = "\"${ext.rider}/bin/rider\"";
          icon = "rider";
          type = "Application";
          # Don't show desktop icon in search or run launcher
          extraConfig.NoDisplay = "true";
        };
      in
      "${desktopFile}/share/applications/jetbrains-rider.desktop";
  };
}
