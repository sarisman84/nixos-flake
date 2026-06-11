{ pkgs, flake-inputs, ... }:
let
  patched-moonlight = (pkgs.callPackage ./moonlight-qt-patched.nix { inherit pkgs; });

  nix-citizen = with pkgs.stdenv.hostPlatform; flake-inputs.nix-citizen.packages.${system};
  nix-gaming = with pkgs.stdenv.hostPlatform; flake-inputs.nix-gaming.packages.${system};
in
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
      patched-moonlight
      steam
      wineWow64Packages.stable
      winetricks
      #rusty-path-of-building
      #(callPackage ./modrinth-patched.nix { inherit pkgs; })
      prismlauncher
      jre
      crossmacro
      pcsx2
      nix-citizen.rsi-launcher
    ];
  };

  services.flatpak.packages = [
    "community.pathofbuilding.PathOfBuilding"
    "sh.ppy.osu"
  ];
}
