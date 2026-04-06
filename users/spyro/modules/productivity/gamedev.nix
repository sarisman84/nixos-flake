{ pkgs, flake-inputs , ... }:
let 
    ext = import ./vscode/packaged_vscode.nix {inherit pkgs;};
in
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
                #ext.vscode
                jetbrains-toolbox
                jetbrains.rider
             ];
           })
           figma-linux
           pandoc
           p7zip
           rar
        ];
    };
}