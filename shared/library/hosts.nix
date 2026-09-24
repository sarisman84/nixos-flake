{
  lib,
  utilities,
  ...
}: {
  # Import all .nix files from a directory as an attrset keyed by filename.
  # Returns { value = <attrset>, logs = [ ] }.
  mkSharedImports = directory: let
    modules = utilities.getNixFileNames directory;
    result = builtins.listToAttrs (
      map (module: {
        name = lib.removeSuffix ".nix" module;
        value = import "${directory}/${module}";
      })
      modules
    );
  in {
    value = result;
    logs = [
      {
        level = 1;
        msg = "hosts: imported shared modules: ${toString (lib.attrNames result)}";
      }
    ];
  };

  # Evaluate all host.nix files under hostsDir via evalModules.
  # Returns { value = spyroFlake.hosts, logs = [ ] }.
  getHosts = hostsDir: projectTypes: let
    hostEntries = utilities.getDirectoryNames hostsDir;
    hostModules =
      map (entry: hostsDir + "/${entry}/host.nix") hostEntries;

    evalHosts = lib.evalModules {
      modules = [projectTypes] ++ hostModules;
    };

    config = evalHosts.config.spyroFlake;
  in {
    value = config.hosts;
    logs = [
      {
        level = 2;
        msg = "hosts: ${toString (lib.length hostEntries)} host module(s) found";
      }
      {
        level = 1;
        msg = "hosts: loaded hosts: ${toString (lib.attrNames config.hosts)}";
      }
    ];
  };

  # Resolve the desktop environment path for a host.
  # Returns { value = <path>, logs = [ ] }.
  getDesktopEnv = desktopEnvDir: host: let
    desktopEnv = host.desktopEnv;
    path = "${desktopEnvDir}/${desktopEnv}/default.nix";
  in {
    value = path;
    logs = [
      {
        level = 1;
        msg = "hosts: desktop env = ${desktopEnv}";
      }
    ];
  };
}
