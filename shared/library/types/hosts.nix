{pkgs, ...}:
with pkgs.lib;
{
  options = {
     nixos.machine = {
        system = mkOption {
          default = "x86_64-linux";
          type = with types; str;
          description = "System architecture.";
        };
        users = mkOption {
          default = [ ];
          type = with types; listOf str;
          description = "List of users on the system.";
        };
        desktopEnv = mkOption {
          default = "kde-plasma";
          type = with types; str;
          description = "Desktop environment to use.";
        };
    };
  };
}
