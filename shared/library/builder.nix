{
  lib,
  nixpkgs,
  home-manager,
  inputs,
  ...
}:
let
  utilities = import ./library/utilities.nix { inherit lib; };
  mkPkgs =
    host:
    let
      system = host.system;
      permInsPkgs = host.permittedInsecurePackages;
    in
    (import nixpkgs {
      inherit system;

      config = {
        allowUnfree = true;
        cudaSupport = true;
        permittedInsecurePackages = if permInsPkgs != null then permInsPkgs else [ ];
      };
    });
  mkSharedImports =
    directory:
    let
      moduleEntries = builtins.readDir directory;
      modules = utilities.getNixFileNames moduleEntries;
    in
    builtins.listToAttrs (
      map (module: {
        name = lib.removeSuffix ".nix" module;
        value = import "${directory}/${module}";
      }) modules
    );
  mkNixosUsers =
    userDir: users:
    builtins.listToAttrs (
      map (user: {
        name = user.name;
        value = {
          isNormalUser = true;
          home = user.home;
          extraGroups = user.groups;
        };
      }) users
    );
  mkHomeManagerUsers =
    userDir: users:
    builtins.listToAttrs (
      map (user: {
        name = user.name;
        value = {
          imports = [ "${userDir}/${user.name}/modules" ];
          home = {
            username = user.name;
            homeDirectory = user.home;
            stateVersion = "25.11";
          };
        };
      }) users
    );
in
{
  mkNixosConfig =
    hostsDir: usersDir:
    let
      # Evaluate host machines
      hostModules = map (entry: "${hostsDir}/${entry}/host.nix") (
        builtins.attrNames (builtins.readDir hostsDir)
      );
      evalHosts = lib.evalModules {
        modules = [ ./project-types.nix ] ++ hostModules;
      };
      hosts = builtins.trace (builtins.typeOf evalHosts.config.spyroFlake.hosts) evalHosts.config.spyroFlake.hosts;
      sharedImports = mkSharedImports ../modules;
    in
    map (
      host:
      let
        system = host.system;
        pkgs = mkPkgs host;
        userModules = map (entry: "${usersDir}/${entry}/user.nix") host.users;
        evalUsers = lib.evalModules {
          modules = [ ./project-types.nix ] ++ userModules;
        };
        users = evalUsers.config.spyroFlake.users;

        desktopEnv = import "../../desktop-env/${host.desktopEnv}";
        nixosUsers = mkNixosUsers usersDir users;
        homeManagerUsers = mkHomeManagerUsers usersDir users;
      in
      {
        name = host.name;
        value = lib.nixosSystem {
          inherit pkgs system;
          specialArgs = {
            inherit sharedImports;
            inherit inputs;
          };

          modules = [
            ../modules/general.nix
          ]
          ++ desktopEnv
          ++ map (user: user.system.modules) users
          ++ [
            {
              users.users = nixosUsers;
            }

            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              #home-manager.extraSpecialArgs.flake-inputs = inputs;
              home-manager.extraSpecialArgs = {
                flake-inputs = inputs;
              };
              home-manager.backupFileExtension = "backup";

              home-manager.users = homeManagerUsers;
            }
          ];
        };
      }
    ) hosts;

}
