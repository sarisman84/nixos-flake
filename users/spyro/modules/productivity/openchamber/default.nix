{
  flake-inputs,
  pkgs,
  ...
}:

let
  openchamber = flake-inputs.openchamber.packages.${pkgs.stdenv.hostPlatform.system}.openchamber;

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
