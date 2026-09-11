{ pkgs, ... }:
{
  services.ollama = {
    enable = true;
  };

  home = {
    packages = with pkgs; [
       opencode
       opencode-desktop
       opencode-claude-auth
    ];
  };
}
