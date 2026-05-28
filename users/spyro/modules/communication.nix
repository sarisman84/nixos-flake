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
    "dev.vencord.Vesktop"
    "me.proton.Mail"
  ];
}
