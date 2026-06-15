{ pkgs, flake-inputs, ... }:
let
  patched-moonlight = (pkgs.callPackage ./moonlight-qt-patched.nix { inherit pkgs; });

  nix-citizen = with pkgs.stdenv.hostPlatform; flake-inputs.nix-citizen.packages.${system};
  nix-gaming = with pkgs.stdenv.hostPlatform; flake-inputs.nix-gaming.packages.${system};
in
{
  
  imports = [
    flake-inputs.nix-flatpak.homeManagerModules.nix-flatpak
  ];
  
  programs = {
    lutris.enable = true;
    # rsi-launcher = {
    #   enable = true;
    #   preCommands = ''
    #     export DXVK_NVAPI_SET_NGX_DEBUG_OPTIONS="DLSSIndicator=1,DLSSGIndicator=1"
    #     export VK_LOADER_LAYERS_ENABLE=VK_LAYER_MESA_vram_report_limit
    #     export VK_VRAM_REPORT_LIMIT_HEAP_SIZE=9216
    #     export VK_VRAM_REPORT_LIMIT_DEVICE_ID=0x10de:0x2208
    #   '';
    # };
  };

  home = {
    packages = with pkgs; [
      #moonlight-qt
      patched-moonlight
      steam
      wineWow64Packages.stable
      winetricks
      wine-staging
      #rusty-path-of-building
      #(callPackage ./modrinth-patched.nix { inherit pkgs; })
      prismlauncher
      jre
      crossmacro
      pcsx2
      # nix-citizen.rsi-launcher
    ];
  };

  services.flatpak.packages = [
    "community.pathofbuilding.PathOfBuilding"
    "sh.ppy.osu"
  ];
}
