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

      mkPkgs =
        system:
        (import nixpkgs {
          inherit system;

          config = {
            allowUnfree = true;
            cudaSupport = true;
          };
        });
      
      mkUsers = users: (
        let
          usersList = map(username : (import (usersDir + "/${username}")) users);
          usersByName = builtins.lisToAttr(map((userDir: user: {name = userDir; value = user;}) users usersList));
        in  {
           # Initialize all the users found for the nixos config
           users.users = builtins.mapAttr(username: user: {
             isNormalUser = true;
             home = "/home/${username}";
             description = user.name;
             extraGroups = user.groups or ["wheel"];
           }) usersByName;

           # Initialize all the users found for home manager to work
           home-manager.users = builtins.mapAttrs (
             username:{
               home.username = username;
               home.homeDirectory = "/home/${username}";

               imports = [(usersDir + "/${username}")];
             }) usersByName;
        }
      ) ;
      mkNixosConfig = 
         directory: (
          let
           hostData = import directory;
           system = hostData.system;
           pkgs = mkPkgs system;
           users = hostData.users;
          in lib.nixosSystem {
            inherit pkgs system;
            modules = [
              ./shared/modules
              (directory + "/configuration.nix")
              home-manager.nixosConfigurations.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.extraSpecialArgs.flake-inputs = inputs;
              }
              mkUsers users
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
