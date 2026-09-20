{ pkgs, ... }:
{
  imports = [
    ./gamedev.nix
    ./git.nix
    ./ssh
    ./gpg.nix
    ./vscode
    ./kitty.nix
    ./bash
    ./llm-agent
    ./jetbrains
    ./teams.nix
    ./web.nix
    ./neovim.nix
  ];

  home = {
    packages = with pkgs; [
      gcc
      go
    ];
  };
}
