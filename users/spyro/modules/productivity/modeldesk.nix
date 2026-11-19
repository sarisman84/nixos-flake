{ flake-inputs, pkgs, ... }:

let
  modeldesk = flake-inputs.modeldesk.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # 43120 is the upstream default dashboard port.
  port = 43120;

  # A manually started `modeldesk` (now on PATH) would hold the port and make
  # the unit crash-loop. Fail fast with a clear message instead (same pattern
  # as the openchamber preflight).
  preflight = pkgs.writeShellScript "modeldesk-preflight" ''
    if (exec 3<>/dev/tcp/127.0.0.1/${toString port}) 2>/dev/null; then
      exec 3>&-
      echo "modeldesk: port ${toString port} is already in use; stop the running instance before starting the service." >&2
      exit 1
    fi
  '';
in
{
  # Modeldesk (sarisman84/modeldesk): local web dashboard for managing GGUF
  # files and monitoring llama.cpp / llama-swap. Built from the upstream Go
  # flake.
  home.packages = [ modeldesk ];

  # Always-on (same pattern as the always-on openchamber / llama-swap user
  # services): started at login, so the dashboard is reachable at
  # http://127.0.0.1:43120 for as long as the user is logged in.
  systemd.user.services.modeldesk = {
    Unit.Description = "Modeldesk local model dashboard";
    Service = {
      Type = "exec";
      ExecStartPre = "${preflight}";
      # -open=false: headless service, don't spawn a browser on start.
      ExecStart = "${modeldesk}/bin/modeldesk -port ${toString port} -open=false";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # App-menu launcher that opens the dashboard in the browser (the service
  # runs headless). Mirrors the llama-swap desktop entry.
  xdg.desktopEntries.modeldesk = {
    name = "modeldesk";
    comment = "Open the local modeldesk dashboard";
    exec = "${pkgs.xdg-utils}/bin/xdg-open http://127.0.0.1:${toString port}/";
    icon = "web-browser";
    categories = [ "Development" ];
  };
}
