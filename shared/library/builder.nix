{
  lib,
  nixpkgs,
  home-manager,
  inputs,
  ...
}: let
  # --- Load sub-modules ---------------------------------------------------
  utilities = import ./utilities.nix {inherit lib;};
  logging = import ./logging.nix {inherit lib;};
  pkgsLib = import ./pkgs.nix {inherit lib nixpkgs inputs logging;};
  hostsLib = import ./hosts.nix {inherit lib utilities logging;};
  usersLib = import ./users.nix {inherit lib utilities logging;};

  inherit (logging) info debug;
  inherit (pkgsLib) mkPkgs;
  inherit (hostsLib) mkSharedImports getHosts getDesktopEnv;
  inherit (usersLib) mkNixosUsers mkHomeManagerUsers getUsers;

  # --- Shared constants ---------------------------------------------------
  projectTypes = ./project-types.nix;
  sharedImportsDir = ./../modules;
in {
  # Build a list of { name, value = nixosSystem } for every host.
  #
  # Called from flake.nix:
  #   builtins.listToAttrs (configBuilder.mkNixosConfig hostsDir usersDir desktopDir)
  mkNixosConfig = hostsDir: usersDir: desktopDir: let
    # Evaluate all host.nix files -> spyroFlake.hosts attrset
    hosts = getHosts hostsDir projectTypes;

    # Import shared/modules/*.nix -> { general = <path>, nvidia = <path>, ... }
    sharedImports = mkSharedImports sharedImportsDir;

    # Per-host assembly
    buildHost = hostName: host: let
      hostDir = hostsDir + "/${hostName}";

      # Users for this host
      users = getUsers usersDir host projectTypes;
      nixosUsers = mkNixosUsers users;
      homeManagerUsers = mkHomeManagerUsers usersDir users;

      # Packages
      allPkgs = mkPkgs host;
      pkgs = allPkgs.unstable;
      pkgsStable = allPkgs.stable;

      # Desktop environment
      desktopEnv = getDesktopEnv desktopDir host;

      # Host-specific paths
      hostConfig = hostDir + "/configuration.nix";
      generalSharedModules = sharedImportsDir + "/general.nix";

      # Collect per-user NixOS system modules
      userSystemModules = lib.flatten (
        lib.mapAttrsToList (_: user: user.system-modules) users
      );
    in {
      name = info "builder: building host '${hostName}' (system=${host.system})" hostName;
      value = lib.nixosSystem {
        inherit pkgs;
        system = host.system;

        specialArgs = {
          inherit sharedImports;
          inherit inputs;
          inherit pkgsStable;
        };

        modules =
          [
            # Host configuration
            hostConfig
            desktopEnv
            generalSharedModules

            # Per-user NixOS modules
          ]
          ++ userSystemModules
          ++ [
            # NixOS user accounts
            {
              users.users = nixosUsers;
            }

            # Home Manager
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = {
                flake-inputs = inputs;
                inherit pkgsStable;
              };
              home-manager.backupFileExtension = "backup";
              home-manager.users = homeManagerUsers;
            }
          ];
      };
    };
  in
    debug "builder: building ${toString (lib.length hosts)} host(s)"
    (lib.mapAttrsToList buildHost hosts);
}
