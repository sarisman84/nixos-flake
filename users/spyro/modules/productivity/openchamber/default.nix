{
  flake-inputs,
  pkgs,
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
  }) {
    system = pkgs.stdenv.hostPlatform.system;
  };

  openchamber = ocNixpkgs.callPackage ./package.nix {
    self = openchamberFlake;
    version = (builtins.fromJSON (builtins.readFile (openchamberFlake + "/package.json"))).version;
    opencodeCli = openchamberFlake.packages.x86_64-linux.opencode-cli;
  };

  # 3000 (the upstream default) is held by Obsidian on this host.
  port = 3001;

  # A manually started `openchamber serve` would hold the port and make the
  # unit crash-loop. Fail fast with a clear message instead (same pattern as
  # the llama-swap preflight).
  preflight = pkgs.writeShellScript "openchamber-preflight" ''
    if (exec 3<>/dev/tcp/127.0.0.1/${toString port}) 2>/dev/null; then
      exec 3>&-
      echo "openchamber: port ${toString port} is already in use; stop the running instance (openchamber stop) before starting the service." >&2
      exit 1
    fi
  '';
in
{
  # OpenChamber: web UI / server for OpenCode sessions. The package bundles
  # its own pinned OpenCode CLI (2.x; OpenChamber requires >= 2.0.20, newer
  # than nixpkgs' 1.x line), so it is self-contained.
  home.packages = [ openchamber ];

  # Always-on (same pattern as the always-on llama-swap backend, ADR 0001):
  # a user service started at login, so it runs with the full user session
  # environment (HOME, XDG, ~/.config/environment.d) and sees the same
  # opencode config and projects as a manual run. The UI is then reachable
  # at http://localhost:3001 for as long as the user is logged in; add
  # `loginctl enable-linger spyro` if it should also run before login.
  systemd.user.services.openchamber = {
    Unit = {
      Description = "OpenChamber web UI for OpenCode";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "exec";
      ExecStartPre = "${preflight}";
      ExecStart = "${openchamber}/bin/openchamber serve --host 127.0.0.1 --port ${toString port} --foreground";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
