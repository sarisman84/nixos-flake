{ pkgs
, inputs
, ...
}:
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

  # Auto Update
  system.autoUpgrade = {
    enable = true;
    flake = "/home/flake.nix";
    flags = [
      "--print-build-logs"
      "--commit-lock-file" # If you want to automatically commit the updated flake.lock
    ];
    dates = "02:00";
    randomizedDelaySec = "45min";
  };
  # Garbage Collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 300";
  };
  nix.settings.auto-optimise-store = true;
}
