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
           (unityhub.override {
             extraPkgs = pkgs: [
                vscode
                dotnetCorePackages.sdk_10_0-bin
             ];
           })
           figma-linux
           pandoc
           p7zip
           rar
           dotnetCorePackages.sdk_10_0-bin
        ];
    };
}