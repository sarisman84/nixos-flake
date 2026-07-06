{ nixpkgs, ... }:
{
  mkPkgs = system: extConfig: (import nixpkgs {
    inherit system;
    config = {
      allowUnfree = extConfig.allowUnfree or true;
      cudaSupport = extConfig.cudaSupport or true;
      permittedInsecurePackages = extConfig.permittedInsecurePackages or [ ];
    };
  });
}
