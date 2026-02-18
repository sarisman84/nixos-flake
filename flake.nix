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

    anime-launchers = {
      url = "github:ezKEa/aagl-gtk-on-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ nixpkgs
    , home-manager
    , nix-flatpak
    , ...
    }:
    let
      utilities = import ./shared/utilities.nix { inherit lib; };
      configBuilder = import ./shared/configBuilder.nix {inherit lib nixpkgs home-manager inputs; };
      lib = nixpkgs.lib;

      hostsDir = ./hosts;
      usersDir = ./users;

      hostEntries = builtins.readDir hostsDir;
      hostNames = utilities.getDirectoryNames hostEntries;

      nixosSystems = map
        (
          hostName:
          let
            hostPath = hostsDir + "/${hostName}";
          in
          {
            name = hostName;
            value = configBuilder.mkNixosConfig hostPath usersDir;
          }
        )
        hostNames;

    in
    {
      nixosConfigurations = builtins.listToAttrs nixosSystems;
    };
}
