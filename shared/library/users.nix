{lib, ...}: {
  # Build NixOS users.users entries.
  # Returns { value = <attrset>, logs = [ ] }.
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
  in {
    value = result;
    logs = [
      {
        level = 1;
        msg = "users: NixOS users: ${toString (lib.attrNames result)}";
      }
    ];
  };

  # Build home-manager.users entries.
  # Returns { value = <attrset>, logs = [ ] }.
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
  in {
    value = result;
    logs = [
      {
        level = 1;
        msg = "users: Home Manager users: ${toString (lib.attrNames result)}";
      }
    ];
  };

  # Evaluate all user.nix files for a host via evalModules.
  # Returns { value = spyroFlake.users, logs = [ ] }.
  getUsers = usersDir: host: projectTypes: let
    usernames = host.users;
    userModules =
      map (entry: usersDir + "/${entry}/user.nix") usernames;

    evalUsers = lib.evalModules {
      modules = [projectTypes] ++ userModules;
    };

    config = evalUsers.config.spyroFlake;
  in {
    value = config.users;
    logs = [
      {
        level = 2;
        msg = "users: ${toString (lib.length usernames)} user module(s) for host";
      }
      {
        level = 1;
        msg = "users: loaded users: ${toString (lib.attrNames config.users)}";
      }
    ];
  };
}
