{ flake-inputs, pkgs, ... }:
{
  imports = [ flake-inputs.penpot-mcp.homeManagerModules.default ];
  programs.penpot-mcp.enable = true;

  home = {
    packages = with pkgs; [
      penpot-desktop
      pnpm
    ];
  };

}
