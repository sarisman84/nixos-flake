{ pkgs, flake-inputs, ... }:
{
  imports= [
    flake-inputs.nix-citizen.nixosModules.default
  ];
}