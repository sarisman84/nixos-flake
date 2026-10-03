{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
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

    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs"; # this line is optional, prevents downloading two versions of nixpkgs but disables cache
    };
  };

  outputs = inputs @ {
    nixpkgs,
    home-manager,
    nix-flatpak,
    nuhxboard,
    ...
  }: let
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
    desktopDir = ./desktop-env;
  in {
    nixosConfigurations = builtins.listToAttrs (configBuilder.mkNixosConfig hostsDir usersDir desktopDir);

    devShells = lib.genAttrs ["x86_64-linux" "aarch64-linux"] (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        default = pkgs.mkShell {
          packages = [
            pkgs.nix
            pkgs.git
            pkgs.alejandra
            pkgs.shellcheck
            pkgs.jq
          ];
          shellHook = ''
            echo "nixos-flake devShell — see AGENTS.md for layout, commands, and the check/build/deploy workflow."
          '';
        };
      }
    );
  };
}
