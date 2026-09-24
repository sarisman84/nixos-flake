{lib, ...}: {
  # Build NixOS users.users entries.
  mkNixosUsers = users:
    builtins.listToAttrs (
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

  # Build home-manager.users entries.
  mkHomeManagerUsers = userDir: users:
    builtins.listToAttrs (
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

  # Evaluate all user.nix files for a host via evalModules.
  getUsers = usersDir: host: projectTypes: let
    usernames = host.users;
    userModules =
      map (entry: usersDir + "/${entry}/user.nix") usernames;

    evalUsers = lib.evalModules {
      modules = [projectTypes] ++ userModules;
    };
  in
    evalUsers.config.spyroFlake.users;
}
