{ pkgs, ... }:
{
  imports = [
    ./rsi-launcher.nix
    ./maplestory.nix
    # ./nuhxboard.nix
  ];

  environment.systemPackages = [
    pkgs.crossmacro
  ];
}
