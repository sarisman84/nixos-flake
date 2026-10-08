{
  registry,
  localModels,
  localProviderId,
  defaultRef,
}: let
  mkOpencodeLimit = entry: let
    opts =
      if entry ? options && builtins.isAttrs entry.options
      then entry.options
      else {};
    ctxSize =
      if (opts ? ctxSize) && builtins.isInt opts.ctxSize && opts.ctxSize > 0
      then opts.ctxSize
      else 65536;
    outputLimit =
      if (opts ? outputLimit) && builtins.isInt opts.outputLimit && opts.outputLimit > 0
      then opts.outputLimit
      else if ctxSize >= 65536
      then 16384
      else 8192;
  in {
    context = ctxSize;
    output = outputLimit;
  };

  # Auxiliary traffic is pinned to the efficient path: the local entry with
  # the smallest context window (efficient stays small by map convention),
  # alphabetical tiebreak. Independent of the session default on purpose.
  smallModelRef = let
    names = builtins.attrNames localModels;
    ctxOf = name: (mkOpencodeLimit localModels.${name}).context;
    sorted = builtins.sort (a: b:
      if ctxOf a != ctxOf b
      then ctxOf a < ctxOf b
      else a < b)
    names;
  in
    if sorted == []
    then "llama.cpp/qwen3-8b"
    else "llama.cpp/${builtins.head sorted}";

  opencodeModels =
    builtins.mapAttrs
    (name: entry: {
      name =
        if (entry ? displayName) && builtins.isString entry.displayName
        then entry.displayName
        else name;
      limit = mkOpencodeLimit entry;
    })
    localModels;

  opencodeConfig = {
    "$schema" = "https://opencode.ai/config.json";
    model = defaultRef;
    small_model = smallModelRef;
    mcp = {
      figma = {
        type = "local";
        command = ["npx" "-y" "figma-developer-mcp" "--stdio"];
        environment = {
          FIGMA_API_KEY = "{env:FIGMA_API_KEY}";
        };
        enabled = true;
        timeout = 15000;
      };
      stitch = {
        type = "remote";
        url = "https://stitch.googleapis.com/mcp";
        enabled = true;
        headers = {
          X-Goog-Api-Key = "{env:STITCH_API_KEY}";
        };
      };
      supabase = {
        type = "remote";
        url = "https://mcp.supabase.com/mcp?project_ref=udqxgbtdufmiybpzrqii&features=docs%2Caccount%2Cdatabase%2Cdebugging%2Cdevelopment%2Cfunctions%2Cbranching";
        enabled = true;
      };
    };
    provider = {
      ${localProviderId} = {
        npm = "@ai-sdk/openai-compatible";
        name = "llama server (local)";
        options = {
          baseURL = "http://127.0.0.1:8080/v1";
          logsDirectory = "\${HOME}/.config/nixos-flake/users/spyro/modules/productivity/llm-agent/logs";
          logFile = "opencode-llama-server.log";
        };
        models = opencodeModels;
      };
    };
    plugin = ["opencode-parser"];
  };
in {
  inherit opencodeConfig;
  files = {
    ".config/opencode/opencode.json".text = builtins.toJSON opencodeConfig;
    ".config/opencode/AGENTS.md".source = ./AGENTS.md;
  };
}
