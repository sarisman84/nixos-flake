{
  pkgs,
  ...
}:
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Flatpak
  services.flatpak.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    git
    gh
    home-manager
    gnumake
    vim
    protonplus
    nixpkgs-fmt
    nixfmt
    nixd
    just
    sonobus
    nodejs
    #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    #  wget
  ];
}
