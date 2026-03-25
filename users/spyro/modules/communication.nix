{ pkgs, flake-inputs, ... }:
{
  imports = [
    flake-inputs.nix-flatpak.homeManagerModules.nix-flatpak
  ];

  home = {
    packages = with pkgs; [
      thunderbird
    ];
  };

  services.flatpak.packages = [
    "com.discordapp.Discord"
  ];
}
