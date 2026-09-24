{
  lib,
  nixpkgs,
  home-manager,
  inputs,
  ...
}:
let
  utilities = import ./utilities.nix { inherit lib; };

  debug =
    msg: value:
    if (builtins.getEnv "NIXOS_DEBUG") != null && (builtins.getEnv "NIXOS_DEBUG") != ""
    then builtins.trace msg value
    else value;

  mkPkgs =
    host:
    let
      system = host.system;
      permInsPkgs = host.permittedInsecurePackages;

      pkgsConfig = {
        allowUnfree = true;
        cudaSupport = true;
        permittedInsecurePackages = if permInsPkgs != null then permInsPkgs else [ ];
      };
    in
    {
      unstable = import nixpkgs {
        inherit system;
        config = pkgsConfig;
      };
      stable = import inputs.nixpkgs-stable {
        inherit system;
        config = pkgsConfig;
      };
    };

  mkSharedImports =
    directory:
    let
      modules = utilities.getNixFileNames directory;
      result = builtins.listToAttrs (
        map (module: {
          name = lib.removeSuffix ".nix" module;
          value = import "${directory}/${module}";
        }) modules
      );
    in
    debug "Imported modules: ${toString (lib.mapAttrsToList (name: _: "${directory}/${name}") result)}" result;

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
      hostModules =
        map
        (
          entry:
          let
            path = hostsDir + "/${entry}/host.nix";
          in
          debug "HostModules Entry - Type: ${builtins.typeOf path} | Path: ${path}" path
        )
        (utilities.getDirectoryNames hostsDir);

      hostMods = debug ("HostModules loaded: " + builtins.typeOf hostModules + " - " + toString hostModules) hostModules;

      evalHosts =
        lib.evalModules {
          modules = [ projectTypes ] ++ hostMods;
        };

      config = evalHosts.config.spyroFlake;
    in
    debug ("Hosts loaded: ${toString (lib.attrNames config.hosts)}") config.hosts;

  getUsers =
    usersDir: host: projectTypes:
    let
      users = debug "Users for host: ${toString host.users}" host.users;
      userModules =
        map
        (
          entry:
          let
            path = usersDir + "/${entry}/user.nix";
          in
          debug "UserModules Entry - Type: ${builtins.typeOf path} | Path: ${path}" path
        )
        users;

      userMods = debug ("UserModules loaded: " + builtins.typeOf userModules) userModules;

      evalUsers =
        lib.evalModules {
          modules = [ projectTypes ] ++ userMods;
        };

      config = evalUsers.config.spyroFlake;
    in
    debug ("Users loaded: ${toString (lib.attrNames config.users)}") config.users;

  getDesktopEnv =
    desktopEnvDir: host:
    let
      desktopEnv = debug "Host uses desktop environment: ${toString host.desktopEnv}" host.desktopEnv;
      path = "${desktopEnvDir}/${desktopEnv}/default.nix";
    in
    debug ("Desktop environment selected: ${path}") path;

in
{
  mkNixosConfig =
    hostsDir: usersDir: desktopDir:
    let
      # Evaluate host machines

      projectTypes = ./project-types.nix;
      pt = debug ("Project types loaded: " + builtins.typeOf projectTypes + " - " + toString projectTypes) projectTypes;

      hosts = getHosts hostsDir pt;
      sharedImports = debug "Shared imports loaded" (mkSharedImports ./../modules);
    in
    lib.mapAttrsToList (
      hostName: host:
      let
        hostDir = hostsDir + "/${hostName}";
        users = getUsers usersDir host pt;

        system = debug ("System to use: ${toString host.system}") host.system;
        allPkgs = mkPkgs host;
        pkgs = allPkgs.unstable;
        pkgsStable = allPkgs.stable;

        desktopEnv = getDesktopEnv desktopDir host;

        nixosUsers = mkNixosUsers usersDir users;
        debugNixosUsers = debug ("Users: ${toString (lib.attrNames nixosUsers)}") nixosUsers;

        homeManagerUsers = mkHomeManagerUsers usersDir users;
        debugHomeManagerUsers = debug ("Home Manager Users: ${toString (lib.attrNames homeManagerUsers)}") homeManagerUsers;

        generalSharedModules = ./../modules/general.nix;
        debugGSM = debug ("General Shared Modules: ${toString generalSharedModules}") generalSharedModules;

        hostConfig = (hostDir + "/configuration.nix");
        debugHC = debug ("Host Config: ${toString hostConfig}") hostConfig;
      in
      {
        name = debug ("Host Machine: ${hostName}") hostName;
        value = lib.nixosSystem {
          inherit pkgs system;
          specialArgs = {
            inherit sharedImports;
            inherit inputs;
            inherit pkgsStable;
          };

          modules = [
            debugHC
            desktopEnv
            debugGSM
          ]
          ++ lib.flatten (lib.mapAttrsToList (_usernames: user: user.system-modules) users)
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
                inherit pkgsStable;
              };
              home-manager.backupFileExtension = "backup";

              home-manager.users = debugHomeManagerUsers;
            }
          ];
        };
      }
    ) hosts;

}
