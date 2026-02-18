{ pkgs, ... }:
{

  fonts.fontconfig.enable = true;

  programs = {
    kitty = {
      enable = true;
      themeFile = "Catppuccin-Mocha";
      font =  {
        package = with pkgs; nerd-fonts.fira-code;
        name = "FiraCode";
        size = 10;
      };
    };
  };
}
