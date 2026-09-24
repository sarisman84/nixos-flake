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

            # Per-host automatic Nix GC. Read by builder.nix and threaded into
            # shared/modules/garbage-collection.nix as the `nixGC` specialArg.
            # Defaults to disabled — each host must opt in.
            nixGC = mkOption {
              type = types.submodule (
                { ... }: {
                  options = {
                    enable = mkOption {
                      type = types.bool;
                      default = false;
                      description = "Enable automatic Nix garbage collection for this host.";
                    };

                    dates = mkOption {
                      type = types.str;
                      default = "weekly";
                      description = "Cron schedule for the automatic GC timer (e.g. \"weekly\", \"0 3 * * 1\").";
                    };

                    deleteOlderThan = mkOption {
                      type = types.str;
                      default = "300d";
                      description = "Retention window: value for nix-collect-garbage --delete-older-than.";
                    };
                  };
                }
              );
              default = { };
              description = "Automatic Nix garbage-collection settings for this host (see shared/modules/garbage-collection.nix).";
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
