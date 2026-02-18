{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    thinkfan
  ];
}
