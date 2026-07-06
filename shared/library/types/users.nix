{ pkgs, ... }:
with pkgs.lib;
{
  options = {
    nixos.user = {
      name = mkOption {
        default = "John Doe";
        type = with types; str;
        description = "User's name. (e.g. John Doe)";
      };
      groups = mkOption {
        default = [ "wheel" "networkmanager" ];
        type = with types; listOf str;
        description = "List of groups the user belongs to.";
      };
      pkgsConfig = {
        allowUnfree = mkOption {
          default = true;
          type = with types; bool;
          description = "Allow unfree packages to be installed.";
        };
        cudaSupport = mkOption {
          default = true;
          type = with types; bool;
          description = "Enable CUDA support for nixpkgs.";
        };
        permittedInsecurePackages = mkOption {
          default = [ ];
          type = with types; listOf str;
          description = "List of packages that are insecure but allowed.";
        };
      };
    };
  };
}
