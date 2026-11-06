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
      # gtk2 is marked broken upstream (removal planned before NixOS 27.05,
      # https://github.com/NixOS/nixpkgs/issues/410814). It is still in the
      # closure via lutris (whose buildFHSEnv rootfs links it), and nixpkgs'
      # default problems matcher turns "broken" into an evaluation error, so
      # downgrade it to a warning until lutris drops gtk2.
      problems.handlers = {
        "gtk+".broken = "warn";
      };
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
