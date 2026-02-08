{ pkgs, ... }:
{
    programs = {
        lutris.enable = true;
    };

    home = {
        packages = with pkgs; [
            #moonlight-qt
            (callPackage ./moonlight-qt-patched.nix {inherit pkgs;})
            steam
        ];
    };
}