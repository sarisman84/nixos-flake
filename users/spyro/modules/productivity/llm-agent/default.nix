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

   wrapperScript = builtins.readFile ./opencode-wrapper.sh;
  opencodeWrapper = pkgs.writeShellScriptBin "opencode" (
    lib.replaceStrings
      [
        "__env_dir__"
        "__curl_bin__"
        "__llama_bin__"
        "__opencode_bin__"
        "__llama_health_url__"
        "__llama_model__"
        "__llama_host__"
        "__llama_port__"
      ]
      [
        envDir
        "${pkgs.curl}/bin/curl"
        "${pkgsStable.llama-cpp}/bin/llama-server"
        "${pkgs.opencode}/bin/opencode"
        llamaHealthUrl
        llamaModel
        llamaHost
        llamaPort
      ]
      wrapperScript
  );
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
