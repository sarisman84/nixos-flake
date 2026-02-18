{...}:
{
  programs.bash.enable = true;
  programs.starship = {
     enable = true;
     enableBashIntegration = true;
     settings = builtins.fromToml (builtins.readFile ./starship_config.toml);
  };
}
