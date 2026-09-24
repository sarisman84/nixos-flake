{
  lib,
  utilities,
  logging,
  ...
}: let
  inherit (logging) info debug;
in {
  # Build NixOS users.users entries from the evaluated user attrset.
  mkNixosUsers = users: let
    result = builtins.listToAttrs (
      lib.mapAttrsToList (username: user: {
        name = username;
        value = {
          isNormalUser = true;
          home = user.home;
          extraGroups = user.groups;
        };
      })
      users
    );
  in
    info "users: NixOS users: ${toString (lib.attrNames result)}" result;

  # Build home-manager.users entries from the evaluated user attrset.
  mkHomeManagerUsers = userDir: users: let
    result = builtins.listToAttrs (
      lib.mapAttrsToList (username: user: {
        name = username;
        value = {
          imports = ["${userDir}/${username}/modules"];
          home = {
            username = username;
            homeDirectory = user.home;
            stateVersion = "25.11";
          };
        };
      })
      users
    );
  in
    info "users: Home Manager users: ${toString (lib.attrNames result)}" result;

  # Evaluate all user.nix files for a host via evalModules.
  # Returns the spyroFlake.users attrset.
  getUsers = usersDir: host: projectTypes: let
    usernames = host.users;
    userModules =
      map
      (
        entry: let
          path = usersDir + "/${entry}/user.nix";
        in
          debug "users: loading ${path}" path
      )
      usernames;

    userMods = debug "users: ${toString (lib.length userModules)} user module(s) collected" userModules;

    evalUsers = lib.evalModules {
      modules = [projectTypes] ++ userMods;
    };

    config = evalUsers.config.spyroFlake;
  in
    info "users: loaded users: ${toString (lib.attrNames config.users)}" config.users;
}
