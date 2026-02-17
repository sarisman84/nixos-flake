{ pkgs, ... }:
{
  fonts.fontconfig.enable = true;
  
  programs = {
    kitty = {
      enable = true;
      themeFile = "Catppuccin-Mocha";
      font =  {
        package = with pkgs; monaspace;
        name = "Monaspace Krypton";
        size = 10;
      };
    };
  };
}
