{
  lib,
  nixpkgs,
  home-manager,
  inputs,
  ...
}:
let
  utilities = import ./utilities.nix { inherit lib; };
  mkPkgs =
    host:
    let
      system = builtins.traceVerbose (host.system) host.system;
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
      dir = builtins.trace ("Directory: ${directory}") directory;
      modules = utilities.getNixFileNames dir;
      result = builtins.listToAttrs (
        map (module: {
          name = lib.removeSuffix ".nix" module;
          value = import "${directory}/${module}";
        }) modules
      );
    in
    builtins.trace ("Imported modules: ${toString (lib.mapAttrsToList (name: value: "${directory}/${name}") result)}") result;

  mkNixosUsers =
    userDir: users:
    builtins.listToAttrs (
      lib.mapAttrsToList (username: user: {
        name = username;
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
      lib.mapAttrsToList (username: user: {
        name = username;
        value = {
          imports = [ "${userDir}/${username}/modules" ];
          home = {
            username = username;
            homeDirectory = user.home;
            stateVersion = "25.11";
          };
        };
      }) users
    );

  getHosts =
    hostsDir: projectTypes:
    let
      hostModules = map (
        entry:
        let
          path = hostsDir + "/${entry}/host.nix";
        in
        builtins.trace ("HostModules Entry - Type: ${builtins.typeOf (path)} | Path:" + path) path

      ) (utilities.getDirectoryNames hostsDir);

      hostMods = builtins.trace (
        "HostModules loaded: " + builtins.typeOf hostModules + " - " + toString (hostModules)
      ) hostModules;

      evalHosts = builtins.trace "Evaluating host modules" lib.evalModules {
        modules = [ projectTypes ] ++ hostMods;
      };

      config = evalHosts.config.spyroFlake;
    in
    builtins.trace ("Hosts loaded: ${toString (lib.mapAttrsToList (name: value: name) config.hosts)}") config.hosts;

  getUsers =
    usersDir: host: projectTypes:
    let
      users = builtins.trace "Users for host: ${toString (host.users)}" host.users;
      userModules = map (
        entry:
        let
          path = usersDir + "/${entry}/user.nix";
        in
        builtins.trace ("UserModules Entry - Type: ${builtins.typeOf (path)} | Path:" + path) path
      ) users;

      userMods = builtins.trace ("UserModules loaded: " + builtins.typeOf userModules) userModules;
      evalUsers = builtins.trace "Evaluating user modules" lib.evalModules {
        modules = [ projectTypes ] ++ userMods;
      };

      config = evalUsers.config.spyroFlake;
    in
    builtins.trace ("Users loaded: ${toString (lib.mapAttrsToList (name: value: name) config.users)}") config.users;

in
{
  mkNixosConfig =
    hostsDir: usersDir:
    let
      # Evaluate host machines

      projectTypes = ./project-types.nix;
      pt = builtins.trace (
        "Project types loaded: " + builtins.typeOf projectTypes + " - " + toString (projectTypes)
      ) projectTypes;

      hosts = getHosts hostsDir pt;
      sharedImports = builtins.trace "Shared imports loaded" (mkSharedImports ./../modules);
    in
    lib.mapAttrsToList (
      hostName: host:
      let
        hostDir = hostsDir + "/${hostName}";
        users = getUsers usersDir host pt;

        system = builtins.trace ("System to use: ${toString (host.system)}") host.system;
        pkgs = mkPkgs host;

        desktopEnv = ./../../desktop-env/kde-plasma/default.nix;

        nixosUsers = mkNixosUsers usersDir users;
        debugNixosUsers = builtins.trace ("Users: ${toString (lib.mapAttrsToList (name: value: name) nixosUsers)}") nixosUsers;

        homeManagerUsers = mkHomeManagerUsers usersDir users;
        debugHomeManagerUsers = builtins.trace ("Home Manager Users: ${toString (lib.mapAttrsToList (name: value: name) homeManagerUsers)}") homeManagerUsers;

        generalSharedModules = ./../modules/general.nix;
        debugGSM = builtins.trace ("General Shared Modules: ${toString generalSharedModules}") generalSharedModules;

        hostConfig = (hostDir + "/configuration.nix");
        debugHC = builtins.trace ("Host Config: ${toString hostConfig}") hostConfig;
      in
      {
        name = builtins.trace ("Host Machine: ${toString (hostName)}") hostName;
        value = lib.nixosSystem {
          inherit pkgs system;
          specialArgs = {
            inherit sharedImports;
            inherit inputs;
          };

          modules = [
            debugHC
            desktopEnv
            debugGSM

          ]
          ++ lib.flatten (lib.mapAttrsToList (usernames: user: user.system-modules) users)
          ++ [
            {
              users.users = debugNixosUsers;
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

              home-manager.users = debugHomeManagerUsers;
            }
          ];
        };
      }
    ) hosts;

}
