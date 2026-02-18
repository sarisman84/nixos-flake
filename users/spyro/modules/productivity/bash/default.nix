{...}:
{
  programs.bash.enable = true;
  programs.starship = {
     enable = true;
     enableBashIntegration = true;
     settings = builtins.fromTOML (builtins.readFile ./starship_config.toml);
  };
}
