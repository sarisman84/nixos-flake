{ pkgs, flake-inputs , ... }:
let 
    vs = import ./vscode/packaged_vscode.nix {inherit pkgs;};
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
                vs.code
             ];
           })
           figma-linux
           pandoc
           p7zip
           rar
        ];
    };
}