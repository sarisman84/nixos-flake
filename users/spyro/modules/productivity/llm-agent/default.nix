{
  config,
  pkgs,
  pkgsStable,
  lib,
  ...
}:
let
  modelsFile = ./models.json;
  models = builtins.fromJSON (builtins.readFile modelsFile);

  modelsDir = "${config.home.homeDirectory}/.local/share/llama.cpp/models";

  llamaModel = "unsloth/Qwen3.8-27B-GGUF:UD-Q6_K_M";
  llamaHost = "127.0.0.1";
  llamaPort = "8080";
  llamaHealthUrl = "http://${llamaHost}:${llamaPort}/health";

  opencodeWrapper = pkgs.writeShellScriptBin "opencode" ''
    set -euo pipefail

    curl_bin="${pkgs.curl}/bin/curl"
    llama_bin="${pkgsStable.llama-cpp}/bin/llama-server"
    opencode_bin="${pkgs.opencode}/bin/opencode"
    log_file="/tmp/opencode-llama-server.log"
    server_pid=""

    cleanup() {
      if [ -n "$server_pid" ]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
      fi
    }

    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    if ! "$curl_bin" --fail --silent --show-error "${llamaHealthUrl}" >/dev/null 2>&1; then
      echo "Starting llama-server for ${llamaModel}"
      "$llama_bin" --hf "${llamaModel}" --host "${llamaHost}" --port "${llamaPort}" >"$log_file" 2>&1 &
      server_pid=$!

      for _ in $(seq 1 180); do
        if "$curl_bin" --fail --silent "$llamaHealthUrl" >/dev/null 2>&1; then
          break
        fi

        if ! kill -0 "$server_pid" 2>/dev/null; then
          echo "llama-server exited during startup" >&2
          tail -n 50 "$log_file" >&2 || true
          exit 1
        fi

        sleep 1
      done

      if ! "$curl_bin" --fail --silent "$llamaHealthUrl" >/dev/null 2>&1; then
        echo "llama-server did not become healthy in time" >&2
        tail -n 50 "$log_file" >&2 || true
        exit 1
      fi
    fi

    "$opencode_bin" "$@"
  '';

  # One shell snippet per model: skip the download if the file already
  # exists, otherwise fetch it into a .tmp file and only rename on success
  # (so a half-downloaded file never looks "done" to a later activation run).
  # downloadModelScript = lib.concatStringsSep "\n" (
  #   map (m: ''
  #     if [ -f "${modelsDir}/${m.name}" ]; then
  #       echo "llama.cpp model already present: ${m.name}"
  #     else
  #       echo "Downloading llama.cpp model: ${m.name}"
  #       ${pkgs.curl}/bin/curl -L --fail --retry 3 \
  #         -o "${modelsDir}/${m.name}.part" "${m.url}"
  #       mv "${modelsDir}/${m.name}.part" "${modelsDir}/${m.name}"
  #     fi
  #   '') models
  # );
in
{
  home.packages = [
    pkgsStable.llama-cpp
    pkgsStable.llama-swap
    opencodeWrapper
    pkgs.opencode-desktop
    pkgs.opencode-claude-auth
  ];

  # home.sessionPath = [ "$HOME/.local/bin" ];

  # home.activation.llamaCppModels = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  #   run mkdir -p "${modelsDir}"
  #   ${downloadModelScript}
  # '';

}
