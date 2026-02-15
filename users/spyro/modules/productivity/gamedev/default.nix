{ pkgs, flake-inputs , ... }:
{
    imports = [
       flake-inputs.nix-flatpak.homeManagerModules.nix-flatpak
    ];
    programs = {
        obsidian.enable = true;
    };

    home = {
        packages = with pkgs; [
           godot
           unityhub
           figma-linux
           pandoc
        ];
    };
}