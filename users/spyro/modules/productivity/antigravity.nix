{pkgs, ...}:
{
  home = {
    packages = with pkgs; [
      antigravity-ide
    ];
  };
}