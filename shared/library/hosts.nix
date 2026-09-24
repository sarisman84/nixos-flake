{
  lib,
  utilities,
  logging,
  ...
}: let
  inherit (logging) info debug;
in {
  # Import all .nix files from a directory as an attrset keyed by filename (without .nix).
  mkSharedImports = directory: let
    modules = utilities.getNixFileNames directory;
    result = builtins.listToAttrs (
      map (module: {
        name = lib.removeSuffix ".nix" module;
        value = import "${directory}/${module}";
      })
      modules
    );
  in
    info "hosts: imported shared modules: ${toString (lib.attrNames result)}" result;

  # Evaluate all host.nix files under hostsDir via evalModules.
  # Returns the spyroFlake.hosts attrset.
  getHosts = hostsDir: projectTypes: let
    hostEntries = utilities.getDirectoryNames hostsDir;
    hostModules =
      map
      (
        entry: let
          path = hostsDir + "/${entry}/host.nix";
        in
          debug "hosts: loading ${path}" path
      )
      hostEntries;

    hostMods = debug "hosts: ${toString (lib.length hostModules)} host module(s) collected" hostModules;

    evalHosts = lib.evalModules {
      modules = [projectTypes] ++ hostMods;
    };

    config = evalHosts.config.spyroFlake;
  in
    info "hosts: loaded hosts: ${toString (lib.attrNames config.hosts)}" config.hosts;

  # Resolve the desktop environment path for a host.
  # Returns the path to desktop-env/<name>/default.nix.
  getDesktopEnv = desktopEnvDir: host: let
    desktopEnv = host.desktopEnv;
    path = "${desktopEnvDir}/${desktopEnv}/default.nix";
  in
    info "hosts: desktop env = ${desktopEnv} (path: ${path})" path;
}
