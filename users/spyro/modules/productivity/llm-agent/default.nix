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
    pkgs.opencode
    pkgs.opencode-desktop
    pkgs.opencode-claude-auth
  ];

  # home.sessionPath = [ "$HOME/.local/bin" ];

  # home.activation.llamaCppModels = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  #   run mkdir -p "${modelsDir}"
  #   ${downloadModelScript}
  # '';

}
