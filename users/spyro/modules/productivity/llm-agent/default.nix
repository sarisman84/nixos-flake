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
  envDir = "${config.home.homeDirectory}/config/nixos-flake/users/spyro/modules/productivity/llm-agent/env";

  opencodeWrapper = pkgs.writeShellScriptBin "opencode" ''
    set -euo pipefail
    log_file="/tmp/opencode-llama-server.log"
    exec > "$log_file" 2>&1 &

    env_dir="${envDir}"
    if [ -d "$env_dir" ]; then
      for env_file in "$env_dir"/*.env; do
        [ -e "$env_file" ] || continue
        set -a
        . "$env_file"
        set +a
      done
    fi

    curl_bin="${pkgs.curl}/bin/curl"
    llama_bin="${pkgsStable.llama-cpp}/bin/llama"
    opencode_bin="${pkgs.opencode}/bin/opencode"
    log_file="/tmp/opencode-llama-server.log"
    server_pid=""

        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
      fi
    }

    trap cleanup EXIT
    cleanup() {
      if [ -n "$server_pid ] ]; then
        kill "$server_pid" 2>/dev/null || true
    }
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
      fi
    }
0        kill "$server_pid" 2>/dev/null || true
      fi
    fi

    "$opencode_bin" "$@"
  '';
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

  home.file.".config/opencode/opencode.json".source = ./opencode.json;

  # home.sessionPath = [ "$HOME/.local/bin" ];

  # home.activation.llamaCppModels = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  #   run mkdir -p "${modelsDir}"
  #   ${downloadModelScript}
  # '';

}
