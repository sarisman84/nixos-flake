{ pkgs, lib, ... }:
let
  utilities = import ./utilities.nix { inherit lib; };
  userOptionType = import ../types/users.nix { inherit pkgs; };
in
{
  mkImportUsers = usersDir: usernames:
    let
      # Evaluates a single user.nix as a NixOS module, returning resolved config
      evalUserModule = usersDir: username:
        let
          userPath = "${usersDir}/${username}/user.nix";
          result = pkgs.lib.evalModules {
            modules = [
              (import userPath) # User's module
              userOptionType # Option Type file
            ];
            specialArgs = { inherit pkgs; };
          };
        in
        result.config.nixos.user;
      # Evaluate all users modules and collect their configs from usernames
      allUsers = map(user: evalUserModule usersDir user) usernames;

      # Generate configs for nixos users
      mkNixosUsers = lib.listToAttrs (map(user: {
        name = user.name;
        value = {
          isNormalUser = true;
          home = "/home/${user.name}";
          extraGroups = user.groups or ["wheel"];
        };
      }) allUsers);
      
      # Generate configs for Home Manager users
      mkHomeManagerUsers = lib.listToAttrs (map(username:     
      {
        name = username;
        value = {
          imports = ["${usersDir}/${username}/modules"];
          home = {
            username = username;
            homeDirectory = "/home/${username}";
            stateVersion = "25.11";
          };
        };
      }) usernames);

      mkUserSystemModules = lib.listToAttrs (map(user:{
        name = user.name;
        value = {
          
        };
      }) allUsers);
    in
    { };

  # mkImportUsers = usersDir:
  #   usernames:
  #   let
  #     mkUserData = map
  #       (username:
  #         let
  #           directory = (usersDir + "/${username}");
  #           userData = import (directory + "/user.nix");
  #           moduleEntries = builtins.readDir userData.system.modules;
  #           modules = utilities.getNixFileNames moduleEntries;
  #         in
  #         {
  #           name = username;
  #           value = {
  #             description = userData.name;
  #             groups = userData.groups;
  #             homeDirectory = "/home/${username}";
  #             systemModules = map
  #               (module: {
  #                 name = lib.removeSuffix ".nix" module;
  #                 value = import "${directory}/${module}";
  #               })
  #               modules;
  #             pkgsConfig = userData.pkgsConfig or { };
  #             inherit directory;
  #           };
  #         })
  #       usernames;
  #     mkDefineNixosUsers = userData: builtins.listToAttrs (
  #       map
  #         (user: {
  #           name = user.name;
  #           value = {
  #             isNormalUser = true;
  #             home = "/home/${user.name}";
  #             extraGroups = user.groups or [ "wheel" ];
  #           };
  #         })
  #         userData
  #     );
  #     mkDefineHomeManagerUsers = userData: builtins.listToAttrs (
  #       map
  #         (user: {
  #           name = user.name;
  #           value = {
  #             imports = [ (user.value.directory + "/modules") ];
  #             home = {
  #               username = user.name;
  #               homeDirectory = user.value.homeDirectory;
  #               stateVersion = "25.11";
  #             };
  #           };
  #         })
  #         userData
  #     );
  #   in
  #   {
  #     nixos.users = mkDefineNixosUsers mkUserData;
  #     home-manager.users = mkDefineHomeManagerUsers mkUserData;
  #     system = {
  #       modules = map
  #         (user: {
  #           name = user.name;
  #           value = user.systemModules;
  #         })
  #         mkUserData;
  #       pkgsConfigs = map
  #         (user: {
  #           name = user.name;
  #           value = user.pkgsConfig or { };
  #         })
  #         mkUserData;
  #     };
  #   };
}
