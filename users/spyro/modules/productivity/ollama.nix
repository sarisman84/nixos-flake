{ pkgs, ... }:
{
  services.ollama = { 
    enable = true;
  };

  home = {
    packages = with pkgs; [
       claude-code
    ];
  };
}
