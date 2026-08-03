{ pkgs, ... }:
{
  imports = [
    ./rsi-launcher.nix
    # ./nuhxboard.nix
  ];

  environment.systemPackages = [
    pkgs.crossmacro
  ];
}
