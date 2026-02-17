{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
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

      mkPkgs =
        system:
        (import nixpkgs {
          inherit system;

          config = {
            allowUnfree = true;
            cudaSupport = true;
          };
        });

      importUsers =
        usernames:
        map (
          username:
          let
            directory = (usersDir + "/${username}");
            userData = import (directory + "/user.nix");
            #homeData = import directory;
          in
          {
            name = username;
            value = {
              description = userData.name;
              groups = userData.groups;
              homeDirectory = "/home/${username}";
              inherit directory;
            };
          }
        ) usernames;

      mkHomeUsers = users : builtins.listToAttrs (
                  map (user: {
                    name = user.name;
                    value = {
                      imports = [(user.value.directory + "/modules")];
                      home = {
                        username = user.name;
                        homeDirectory = user.value.homeDirectory;
                        stateVersion = "25.11";
                        
                      };
                    };
                  }) users
                );
      mkNixosConfig =
        directory:
        (
          let
            hostData = import directory;
            system = hostData.system;
            pkgs = mkPkgs system;
            users = importUsers hostData.users;
          in
          lib.nixosSystem {
            inherit pkgs system;
            modules = [
              ./shared/modules
              (directory + "/configuration.nix")
              (
                {
                  # ---- NIXOS USERS ----
                  users.users = builtins.listToAttrs (
                    map (user: {
                      name = user.name;
                      value = {
                        isNormalUser = true;
                        home = "/home/${user.name}";
                        extraGroups = user.groups or [ "wheel" ];
                      };
                    }) users
                  );
                }
              )
              home-manager.nixosModules.home-manager
              {

                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.extraSpecialArgs.flake-inputs = inputs;

                # ---- HOME MANAGER USERS ----
                home-manager.users = mkHomeUsers users;
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
