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
    hosts = getHosts hostsDir projectTypes;
    sharedImports = mkSharedImports sharedImportsDir;

    buildHost = hostName: host: let
      hostDir = hostsDir + "/${hostName}";

      users = getUsers usersDir host projectTypes;
      nixosUsers = mkNixosUsers users;
      homeManagerUsers = mkHomeManagerUsers usersDir users;

      allPkgs = mkPkgs host;
      pkgs = allPkgs.unstable;
      pkgsStable = allPkgs.stable;

      desktopEnv = getDesktopEnv desktopDir host;

      hostConfig = hostDir + "/configuration.nix";
      generalSharedModules = sharedImportsDir + "/general.nix";

      userSystemModules = lib.flatten (
        lib.mapAttrsToList (_: user: user.system-modules) users
      );
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
          ];
      };
    };
  in
    lib.mapAttrsToList buildHost hosts;
}
