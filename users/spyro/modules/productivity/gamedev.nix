{ pkgs, flake-inputs , ... }:
{
    imports = [
       flake-inputs.nix-flatpak.homeManagerModules.nix-flatpak
       ./vscode
    ];
    programs = {
        obsidian.enable = true;
    };

    home = {
        packages = with pkgs; [
           godot
           (unityhub.override {
             extraPkgs = pkgs: [
                vscode-fhs
             ];
           })
           figma-linux
           pandoc
           p7zip
           rar
        ];
    };
}