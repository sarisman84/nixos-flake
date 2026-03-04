{lib, nixpkgs, home-manager, inputs, ...}:
let
   utilities = import ./utilities.nix { inherit lib; };
   mkPkgs =
       system:
       (import nixpkgs {
         inherit system;
 
         config = {
           allowUnfree = true;
           cudaSupport = true;
         };
   });
   
   # Define Users and their permissions
   mkUsers = users: builtins.listToAttrs
   (
     map
       (user: {
         name = user.name;
         value = {
           isNormalUser = true;
           home = "/home/${user.name}";
           extraGroups = user.groups or [ "wheel" ];
         };
       })
       users
   );

  # Define Home Manager Users
  mkHomeUsers = users: builtins.listToAttrs (
    map
      (user: {
        name = user.name;
        value = {
          imports = [ (user.value.directory + "/modules") ];
          home = {
            username = user.name;
            homeDirectory = user.value.homeDirectory;
            stateVersion = "25.11";

          };
        };
      })
      users
  );

    # Define System users for Nix Config
    importUsers =
        usersDir: 
          usernames:
          map
          (
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
          )
         usernames;

    # Compose shared imports automatically
    mkSharedImports = directory :
    let
      moduleEntries = builtins.readDir directory;
      modules = utilities.getFileNames moduleEntries;
    in builtins.listToAttrs(
     map(
      module:{
        name = builtins.replaceStrings [".nix"] [""] module;
        value = {
          inherit module;
        };
      })
      modules
  );
in
{
  mkNixosConfig =
    directory:
    userDirectory:
    (
      let
        hostData = import directory;
        system = hostData.system;
        pkgs = mkPkgs system;
        users = importUsers userDirectory hostData.users ;
        sharedImports = mkSharedImports ./modules;
      in
      lib.nixosSystem {
        inherit pkgs system;
        specialArgs = {
          inherit sharedImports;
        };
        modules = [
          ./modules/general.nix
          (directory + "/configuration.nix")

          {
            # ---- NIXOS USERS ----
            users.users = mkUsers users;
          }

          home-manager.nixosModules.home-manager
          {

            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs.flake-inputs = inputs;
            home-manager.backupFileExtension = "backup";

            # ---- HOME MANAGER USERS ----
            home-manager.users = mkHomeUsers users;
          }
        ];
      }
    );
}
