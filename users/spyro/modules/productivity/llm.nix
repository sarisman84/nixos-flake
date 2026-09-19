{ pkgs, ... }:
{
  home = {
    packages = with pkgs; [
      llama-cpp
      opencode
      opencode-desktop
      opencode-claude-auth
    ];
  };
}
