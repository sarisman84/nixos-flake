{ pkgs, flake-inputs, ... }:
{
  imports = [
    flake-inputs.nix-flatpak.homeManagerModules.nix-flatpak
  ];

  home = {
    packages = with pkgs;[
      jetbrains-toolbox
    ];
  };
}
