{
  lib,
  nixpkgs,
  inputs,
  logging,
  ...
}: let
  inherit (logging) info debug;
in {
  # Build nixpkgs sets (unstable + stable) for a given host.
  # Returns { unstable, stable } — each an evaluated nixpkgs set.
  mkPkgs = host: let
    system = host.system;
    permInsPkgs = host.permittedInsecurePackages;

    pkgsConfig = {
      allowUnfree = true;
      cudaSupport = true;
      permittedInsecurePackages =
        if permInsPkgs != null
        then permInsPkgs
        else [];
    };

    unstable = import nixpkgs {
      inherit system;
      config = pkgsConfig;
    };

    stable = import inputs.nixpkgs-stable {
      inherit system;
      config = pkgsConfig;
    };
  in
    debug "pkgs: building nixpkgs sets for system=${system}"
    (
      info "pkgs: unstable = ${toString unstable.name or "unnamed"}, stable = ${toString stable.name or "unnamed"}"
      {
        inherit unstable stable;
      }
    );
}
