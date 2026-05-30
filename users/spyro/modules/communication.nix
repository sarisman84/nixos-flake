{ pkgs,flake-inputs, ... }:
{
 

  imports = [
    flake-inputs.nix-flatpak.homeManagerModules.nix-flatpak
  ];

  # programs = {
  #   discord.enable = true;
  # };
  # home = {
  #   packages = with pkgs; [
  #     thunderbird
  #   ];
  # };

  services.flatpak.packages = [
    "com.discordapp.Discord"
    "me.proton.Mail"
  ];
}
