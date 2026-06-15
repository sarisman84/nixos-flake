{pkgs, inputs, ...}:
{
   imports = [
     inputs.nix-citizen.nixosModules.default
   ];
}