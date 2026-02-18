{...}:
{
  programs.bash = {
     enable = true;
     shellAliases = {
        dnCount = "ls **/default.nix | wc -l";
        dnlCount = "cat **/default.nix | wc -l";

        check = "git status";
        commit = "git add . && git commit -m";
        linkRepo = "git remote add origin";
        push = "git push";
        pull = "git pull --rebase";
        switch = "git switch";
        create = "git switch -c";
     };
  };
  programs.starship = {
     enable = true;
     enableBashIntegration = true;
     settings = builtins.fromTOML (builtins.readFile ./starship_config.toml);
  };
}
