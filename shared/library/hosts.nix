{
  lib,
  utilities,
  ...
}: {
  # Import all .nix files from a directory as an attrset keyed by filename.
  mkSharedImports = directory: let
    modules = utilities.getNixFileNames directory;
  in
    builtins.listToAttrs (
      map (module: {
        name = lib.removeSuffix ".nix" module;
        value = import "${directory}/${module}";
      })
      modules
    );

  # Evaluate all host.nix files under hostsDir via evalModules.
  getHosts = hostsDir: projectTypes: let
    hostEntries = utilities.getDirectoryNames hostsDir;
    hostModules =
      map (entry: hostsDir + "/${entry}/host.nix") hostEntries;

    evalHosts = lib.evalModules {
      modules = [projectTypes] ++ hostModules;
    };
  in
    evalHosts.config.spyroFlake.hosts;

  # Resolve the desktop environment path for a host.
  getDesktopEnv = desktopEnvDir: host: "${desktopEnvDir}/${host.desktopEnv}/default.nix";
}
