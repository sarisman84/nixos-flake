{ pkgs, pkgsStable, ... }:
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Flatpak
  services.flatpak.enable = true;

  # Fonts
  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
  ];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = [
    pkgs.git
    pkgs.gh
    pkgs.home-manager
    pkgs.gnumake
    pkgs.vim
    pkgs.protonplus
    pkgs.nixpkgs-fmt
    pkgs.nixfmt
    pkgs.nixd
    pkgs.just
    pkgsStable.sonobus
    pkgs.nodejs
    #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    #  wget
  ];
}
