{
  lib,
  nixpkgs,
  home-manager,
  inputs,
  ...
}: let
  utilities = import ./utilities.nix {
    inherit lib;
  };
  logging = import ./logging.nix {
    inherit lib;
  };
  pkgsLib = import ./pkgs.nix {
    inherit lib nixpkgs inputs;
  };
  hostsLib = import ./hosts.nix {
    inherit lib utilities;
  };
  usersLib = import ./users.nix {
    inherit lib;
  };

  inherit (pkgsLib) mkPkgs;
  inherit (hostsLib) mkSharedImports getHosts getDesktopEnv;
  inherit (usersLib) mkNixosUsers mkHomeManagerUsers getUsers;

  projectTypes = ./project-types.nix;
  sharedImportsDir = ./../modules;
in {
  mkNixosConfig = hostsDir: usersDir: desktopDir: let
    hostResult = getHosts hostsDir projectTypes;
    hosts = hostResult.value;

    sharedResult = mkSharedImports sharedImportsDir;
    sharedImports = sharedResult.value;

    buildHost = hostName: host: let
      hostDir = hostsDir + "/${hostName}";

      userResult = getUsers usersDir host projectTypes;
      users = userResult.value;

      nixosUserResult = mkNixosUsers users;
      nixosUsers = nixosUserResult.value;

      hmUserResult = mkHomeManagerUsers usersDir users;
      homeManagerUsers = hmUserResult.value;

      pkgsResult = mkPkgs host;
      pkgs = pkgsResult.value.unstable;
      pkgsStable = pkgsResult.value.stable;

      deResult = getDesktopEnv desktopDir host;
      desktopEnv = deResult.value;

      hostConfig = hostDir + "/configuration.nix";
      generalSharedModules = sharedImportsDir + "/general.nix";

      userSystemModules = lib.flatten (
        lib.mapAttrsToList (_: user: user.system-modules) users
      );

      # Collect all log entries for this host
      hostLogs =
        [
          {
            level = 1;
            msg = "builder: building host '${hostName}' (system=${host.system})";
          }
        ]
        ++ userResult.logs
        ++ nixosUserResult.logs
        ++ hmUserResult.logs
        ++ pkgsResult.logs
        ++ deResult.logs;
    in {
      name = hostName;
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
            hostConfig
            desktopEnv
            generalSharedModules
          ]
          ++ userSystemModules
          ++ [
            {
              users.users = nixosUsers;
            }

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

            # Print evaluation log at activation
            (logging.toModule hostLogs)
          ];
      };
    };
  in
    lib.mapAttrsToList buildHost hosts;
}
