{ pkgs, ... }:
{
  home.packages = with pkgs; [
    fastfetch
  ];

  programs.bash = {
    enable = true;
    initExtra = builtins.readFile ./commands.sh;
    shellAliases = {
      update = "sudo nixos-rebuild switch --flake";

      dnCount = "ls **/default.nix | wc -l";
      dnlCount = "cat **/default.nix | wc -l";

      check = "git status";
      commit = "git add . && git commit -m";
      linkRepo = "git remote add origin";
      push = "git push";
      pull = "git pull --rebase";
      switch = "git switch";
      branches = "git branch";
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
