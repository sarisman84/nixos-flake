{
  lib,
  pkgs,
  config,
  ...
}:
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.systemPackages = with pkgs; [
    git
    home-manager
    gnumake
    vim
    protonplus
    nixpkgs-fmt
    nixfmt
  ];
}
