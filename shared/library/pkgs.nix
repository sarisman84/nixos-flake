{
  lib,
  nixpkgs,
  inputs,
  ...
}: {
  # Build nixpkgs sets (unstable + stable) for a given host.
  # Returns { value = { unstable, stable }, logs = [ ] }.
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
  in {
    value = {
      inherit unstable stable;
    };
    logs = [
      {
        level = 2;
        msg = "pkgs: building nixpkgs sets for system=${system}";
      }
      {
        level = 1;
        msg = "pkgs: unstable=${unstable.name or "?"} stable=${stable.name or "?"}";
      }
    ];
  };
}
