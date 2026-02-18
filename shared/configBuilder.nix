{lib, nixpkgs, home-manager, inputs, ...}:
let
   usersDir = ./users;

   mkPkgs =
       system:
       (import nixpkgs {
         inherit system;
 
         config = {
           allowUnfree = true;
           cudaSupport = true;
         };
   });
 
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

  
    importUsers =
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
in
{
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
          ./shared/modules/general.nix
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
