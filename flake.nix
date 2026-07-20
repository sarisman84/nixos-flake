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

    nix-citizen = {
      url = "github:LovingMelody/nix-citizen";
      inputs.nix-gaming.follows = "nix-gaming";
    };

    nix-gaming = {
      url = "github:fufexan/nix-gaming";
    };

    nuhxboard = {
      url = "github:justdeeevin/nuhxboard";
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
      lib = nixpkgs.lib;
      configBuilder = import ./shared/library/builder.nix {
        inherit
          lib
          nixpkgs
          home-manager
          inputs
          ;
      };

      hostsDir = ./hosts;
      usersDir = ./users;
    in
    {
      nixosConfigurations = builtins.listToAttrs (configBuilder.mkNixosConfig hostsDir usersDir);
    };
}
