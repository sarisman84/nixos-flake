{ pkgs, flake-inputs, ... }:
let
  patched-moonlight = (pkgs.callPackage ./moonlight-qt-patched.nix { inherit pkgs; });
  nix-citizen = flake_inputs.nix-citizen.packages.${system};
  nix-gaming = flake-inputs.nix-gaming.packages.${pkgs.stdenv.hostPlatform.system};
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
      nix-gaming.star-citizen
    ];
  };

  services.flatpak.packages = [
    "community.pathofbuilding.PathOfBuilding"
    "sh.ppy.osu"
  ];
}
