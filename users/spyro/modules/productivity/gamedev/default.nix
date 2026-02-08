{ pkgs, flake-inputs , ... }:
{
    imports = [
       flake-inputs.nix-flatpak.homeManagerModules.nix-flatpak
    ];

    ome = {
        packages = with pkgs; [
           godot
           unityhub
           figma-linux
           pandoc
        ];
    };
}