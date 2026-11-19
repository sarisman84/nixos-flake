{ flake-inputs, pkgs, ... }:
{
  # Modeldesk (sarisman84/modeldesk): local web dashboard for managing GGUF
  # files and monitoring llama.cpp / llama-swap. Built from the upstream Go
  # flake; the dashboard opens at http://127.0.0.1:43120 when launched.
  home.packages = [
    flake-inputs.modeldesk.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
