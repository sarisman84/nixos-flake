{
  flake-inputs,
  lib,
  ...
}:

let
  openchamberFlake = flake-inputs.openchamber;

  # Vendored from the openchamber flake (v2.5.0): package.nix is upstream's
  # own recipe, and hashes.json carries its baked dependency hashes. The
  # bunDeps hash there is stale at the tag (bun.lock moved after the bake;
  # upstream re-bake PR #5154 was still open), so hashes.json carries the
  # re-baked value measured against the openchamber flake's locked nixpkgs.
  #
  # Those hashes were produced with that flake's locked nixpkgs (bun 1.4.2);
  # our nixpkgs has bun 1.3.13, which changes the fixed-output bun-deps
  # hash, so the recipe is built against the openchamber flake's locked
  # nixpkgs rather than ours.
  ocLock = builtins.fromJSON (builtins.readFile (openchamberFlake + "/flake.lock"));
  ocNixpkgs = import (builtins.fetchTree {
    type = "tarball";
    url = "https://api.github.com/repos/NixOS/nixpkgs/tarball/${ocLock.nodes.nixpkgs.locked.rev}";
    narHash = ocLock.nodes.nixpkgs.locked.narHash;
  }) { };

  openchamber = ocNixpkgs.callPackage ./package.nix {
    inherit openchamberFlake;
    self = openchamberFlake;
    version = (builtins.fromJSON (builtins.readFile (openchamberFlake + "/package.json"))).version;
    opencodeCli = openchamberFlake.packages.x86_64-linux.opencode-cli;
  };
in
{
  # OpenChamber: web UI / server for OpenCode sessions. The package bundles
  # its own pinned OpenCode CLI (2.x; OpenChamber requires >= 2.0.20, newer
  # than nixpkgs' 1.x line), so it is self-contained. Run `openchamber` and
  # open http://localhost:3000.
  home.packages = [ openchamber ];
}
