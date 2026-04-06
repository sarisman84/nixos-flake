{ pkgs,lib, flake-inputs , ... }:
let 
    vs_ext = import ./vscode/packaged_vscode.nix {inherit pkgs;};
    jr_ext = import ./jetbrains/patched_jetbrains_rider.nix {inherit pkgs; inherit lib;};
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
                #vs_ext.vscode
                jetbrains-toolbox
                jr_ext.rider
             ];
           })
           figma-linux
           pandoc
           p7zip
           rar
        ];
    };
}