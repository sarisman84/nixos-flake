{ pkgs, flake-inputs , ... }:
{
    imports = [
       flake-inputs.nix-flatpak.homeManagerModules.nix-flatpak
    ];

    home = {
        packages = with pkgs; [
           godot
           unityhub
           figma-linux
           pandoc
        ];
    };
}