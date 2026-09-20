{ pkgs, pkgsStable, ... }:
{
  home = {
    packages = [
      pkgsStable.llama-cpp
      pkgs.opencode
      pkgs.opencode-desktop
      pkgs.opencode-claude-auth
    ];
  };
}
