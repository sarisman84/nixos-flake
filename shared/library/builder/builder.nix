{ lib, nixpkgs, home-manager, inputs, ... }:
let
  utilities = import ./utilities.nix { inherit lib; };

  internalBuilder = {

    mkPkgs = system: extConfig: (import nixpkgs {
      inherit system;
      config = if extConfig != null then extConfig else {
        allowUnfree = true;
        cudaSupport = true;
      };
    });

   

    importUsers = usersDirectory: usernames: map (username: 
    let
    { 

    }) usernames;
  };
in
{ }
