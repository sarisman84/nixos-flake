{ pkgs, ... }:
{
  home.packages = with pkgs; [
    fastfetch
  ];

  programs.bash = {
    enable = true;
    initExtra = ''
      $(builtins.readFile ./commands.sh)
      $(builtins.readFile ./completions.sh)
    '';
    shellAliases = {
      dnCount = "ls **/default.nix | wc -l";
      dnlCount = "cat **/default.nix | wc -l";
    };
    bashrcExtra = ''
      fastfetch
    '';
  };
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    settings = builtins.fromTOML (builtins.readFile ./starship_config.toml);
  };
}
