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
}
