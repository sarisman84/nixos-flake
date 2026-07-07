{
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
in
{
  options.spyroFlake.hosts = mkOption {
    type = types.attrsOf (
      types.submodule (
        { name, ... }: {
          options = {
            system = mkOption {
              type = types.str;
              default = "x86_64-linux";
              description = "System architecture.";
            };

            users = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "List of users on the system.";
            };

            desktopEnv = mkOption {
              type = types.str;
              default = "kde-plasma";
              description = "Desktop environment to use (e.g. kde-plasma, gnome, etc).";
            };

            permittedInsecurePackages = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "List of insecure packages to allow installation of.";
            };
          };
        }
      )
    );

    default = { };
  };

  options.spyroFlake.users = mkOption {
    type = types.attrsOf (
      types.submodule (
        { name, config, ... }: {
          options = {
            groups = mkOption {
              default = [
                "wheel"
                "networkmanager"
              ];
              type = with types; listOf str;
              description = "List of groups the user belongs to.";
            };

            home = mkOption {
              type = with types; str;
              description = "The user's home directory.";
              default = "/home/${name}";
            };

            pfp = mkOption {
              type = types.path;
              default = "";
              description = "Path to the user's profile picture (pfp).";
            };

            system-modules = mkOption {
              default = [ ];
              type = with types; listOf path;
              description = "List of NixOS modules to be included in the user's system configuration.";
            };
          };
        }
      )
    );
    default = { };
  };
}
