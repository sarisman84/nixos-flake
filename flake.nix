{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-flatpak = {
      url = "github:gmodena/nix-flatpak/?ref=latest";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      home-manager,
      nix-flatpak,
      ...
    }:
    let
      utilities = import ./shared/utilities { inherit lib; };
      lib = nixpkgs.lib;

      hostsDir = ./hosts;
      usersDir = ./users;

      hostEntries = builtins.readDir hostsDir;
      hostNames = utilities.getDirectoryNames hostEntries;

      usersList = usernames: map(username : (import (usersDir + "/${username}")) usernames);
      usersByName = usernames: builtins.listToAttr(map((userDir: user: {name = userDir; value = user;}) usernames usersList));

      mkPkgs =
        system:
        (import nixpkgs {
          inherit system;

          config = {
            allowUnfree = true;
            cudaSupport = true;
          };
        });
      # mkUserAcc = users: ({...}: {
      #   users.users = builtins.mapAttrs(username: user: {
      #        isNormalUser = true;
      #        home = "/home/${username}";
      #        description = user.name;
      #        extraGroups = user.groups or ["wheel"];
      #      }) usersByName;
      # })  ;
      # mkUsers = users: {
      #      # Initialize all the users found for home manager to work
      #      home-manager.users = builtins.mapAttrs (
      #        username:{
      #          home.username = username;
      #          home.homeDirectory = "/home/${username}";

      #          imports = (usersDir + "/${username}/default.nix");
      #        }) usersByName;
      # };
      importUsers = usernames : 
        let
        in
        {

        };
           

      mkNixosConfig = 
         directory: (
          let
           hostData = import directory;
           system = hostData.system;
           pkgs = mkPkgs system;
           users = importUsers hostData.users;
          in lib.nixosSystem {
            inherit pkgs system;
            modules = [
              ./shared/modules
              (directory + "/configuration.nix")
                            ({...}:{
                # ---- NIXOS USERS ----
                users.users = builtins.listToAttrs(map(username: user: {
                  name = username;
                  value = {
                    isNormalUser = true;
                    home = "/home/${username}";
                    extraGroups = user.groups or ["wheel"];
                  }; 
                  }) users);
              })
              home-manager.nixosModules.home-manager
              {
                
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.extraSpecialArgs.flake-inputs = inputs;
                # ---- HOME MANAGER USERS ----
                home-manager.users = builtins.listToAttrs(map(username: user: {
                  name = username;
                  value = {
                    home.username = username;
                    home.homeDirectory = "/home/${username}";
                    imports = [(usersDir + "/${username}")];
                  };
                }));
              }
            ];
          }
         );

      nixosSystems = map (
        hostName:
        let
          hostPath = hostsDir + "/${hostName}";
        in
        {
          name = hostName;
          value = mkNixosConfig hostPath;
        }
      ) hostNames;

    in
    {
      nixosConfigurations = builtins.listToAttrs nixosSystems;
    };
}
