{pkgs, config, lib, inputs, ...}:
{
   imports = [
     inputs.nix-citizen.nixosModules.default
   ];

   nix.settings = {
      substituters = [
        "https://nix-gaming.cachix.org"
        "https://nix-citizen.cachix.org"
      ];
      trusted-public-keys = [
        "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
        "nix-citizen.cachix.org-1:lPMkWc2X8XD4/7YPEEwXKKBg+SVbYTVrAaLA2wQTKCo="
      ];
   };

   programs.rsi-launcher = {
      enable = true;
      preCommands = ''
        export DXVK_NVAPI_SET_NGX_DEBUG_OPTIONS="DLSSIndicator=1,DLSSGIndicator=1"
        export VK_LOADER_LAYERS_ENABLE=VK_LAYER_MESA_vram_report_limit
        export VK_VRAM_REPORT_LIMIT_HEAP_SIZE=9216
        export VK_VRAM_REPORT_LIMIT_DEVICE_ID=0x10de:0x2208
      '';
   };

  # NixOS configuration for Star Citizen requirements
  boot.kernel.sysctl = {
    "vm.max_map_count" = 16777216;
    "fs.file-max" = 524288;
  };
}