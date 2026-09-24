{
  lib,
  nixpkgs,
  inputs,
  ...
}: {
  # Build nixpkgs sets (unstable + stable) for a given host.
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
    inherit unstable stable;
  };
}
