{ config, pkgs, lib, ... }:
let
  llamaModel = "unsloth/Qwen3.8-27B-GGUF:UD-Q6_K_M";
  llamaHost = "127.0.0.1";
  llamaPort = "8080";
  llamaHealthUrl = "http://${llamaHost}:${llamaPort}/health";
  envDir = "${config.home.homeDirectory}/config/nixos-flake/users/spyro/modules/productivity/llm-agent/env";
  modelsJson = "${config.home.homeDirectory}/config/nixos-flake/users/spyro/modules/productivity/llm-agent/models.json";

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
        "__models_json__"
        "__jq_bin__"
      ]
      [
        envDir
        "${pkgs.curl}/bin/curl"
        "${pkgs.llama-cpp}/bin/llama-server"
        "${pkgs.opencode}/bin/opencode"
        llamaHealthUrl
        llamaModel
        llamaHost
        llamaPort
        modelsJson
        "${pkgs.jq}/bin/jq"
      ]
      wrapperScript
   );
in
{
  home.packages = [
    pkgs.llama-cpp
    pkgs.llama-swap
    opencodeWrapper
    pkgs.opencode-desktop
    pkgs.opencode-claude-auth
  ];

  home.file.".config/opencode/opencode.json".source = ./opencode.json;
  home.file.".config/opencode/AGENTS.md".source = ./AGENTS.md;
}
