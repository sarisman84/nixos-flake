{
  config,
  pkgs,
  lib,
  ...
}: let
  llamaHost = "127.0.0.1";
  llamaPort = "8080";
  llamaHealthUrl = "http://${llamaHost}:${llamaPort}/health";
  envDir = "${config.home.homeDirectory}/config/nixos-flake/users/spyro/modules/productivity/llm-agent/env";
  modelsJson = "${config.home.homeDirectory}/config/nixos-flake/users/spyro/modules/productivity/llm-agent/models.json";

  # Registry validation (ticket #35): models.json is the canonical model
  # registry. Malformed entries must fail `nix flake check` with a readable
  # error, surfaced through home-manager assertions.
  registryParse = builtins.tryEval (builtins.fromJSON (builtins.readFile ./models.json));

  validCacheTypes = ["f32" "f16" "bf16" "q8_0" "q4_0" "q4_1" "iq4_nl" "q5_0" "q5_1"];
  validOptionFields = ["ctxSize" "outputLimit" "gpuLayers" "cacheType" "cacheTypeK" "cacheTypeV" "reasoningBudget" "ttl" "mtpProfile" "extraArgs" "templateOverride"];
  validMtpFields = ["enabled" "specType" "draftModel" "draftTokensMax" "draftCtxSize" "draftCacheTypeK" "draftCacheTypeV"];

  errIf = cond: msg: lib.optional (!cond) msg;

  checkMtpProfile = name: profile:
    if !builtins.isAttrs profile
    then ["model '${name}': 'options.mtpProfile' must be an object"]
    else let
      unknown = builtins.filter (f: !(builtins.elem f validMtpFields)) (builtins.attrNames profile);
    in
      (map (f: "model '${name}': unknown mtpProfile field '${f}'") unknown)
      ++ errIf (!(profile ? enabled) || builtins.isBool profile.enabled) "model '${name}': 'options.mtpProfile.enabled' must be a boolean"
      ++ errIf (!(profile ? specType) || builtins.isString profile.specType) "model '${name}': 'options.mtpProfile.specType' must be a string"
      ++ errIf (!(profile ? draftModel) || builtins.isString profile.draftModel) "model '${name}': 'options.mtpProfile.draftModel' must be a string"
      ++ errIf (!(profile ? draftTokensMax) || (builtins.isInt profile.draftTokensMax && profile.draftTokensMax > 0)) "model '${name}': 'options.mtpProfile.draftTokensMax' must be a positive integer"
      ++ errIf (!(profile ? draftCtxSize) || (builtins.isInt profile.draftCtxSize && profile.draftCtxSize > 0)) "model '${name}': 'options.mtpProfile.draftCtxSize' must be a positive integer"
      ++ errIf (!(profile ? draftCacheTypeK) || (builtins.isString profile.draftCacheTypeK && builtins.elem profile.draftCacheTypeK validCacheTypes)) "model '${name}': 'options.mtpProfile.draftCacheTypeK' must be a KV cache type"
      ++ errIf (!(profile ? draftCacheTypeV) || (builtins.isString profile.draftCacheTypeV && builtins.elem profile.draftCacheTypeV validCacheTypes)) "model '${name}': 'options.mtpProfile.draftCacheTypeV' must be a KV cache type";

  checkOptions = name: opts:
    if !builtins.isAttrs opts
    then ["model '${name}': 'options' must be an object"]
    else let
      unknown = builtins.filter (f: !(builtins.elem f validOptionFields)) (builtins.attrNames opts);
    in
      (map (f: "model '${name}': unknown options field '${f}'") unknown)
      ++ errIf (!(opts ? ctxSize) || (builtins.isInt opts.ctxSize && opts.ctxSize > 0)) "model '${name}': 'options.ctxSize' must be a positive integer"
      ++ errIf (!(opts ? outputLimit) || (builtins.isInt opts.outputLimit && opts.outputLimit > 0)) "model '${name}': 'options.outputLimit' must be a positive integer"
      ++ errIf (!(opts ? gpuLayers) || builtins.isInt opts.gpuLayers) "model '${name}': 'options.gpuLayers' must be an integer (-1 = full offload)"
      ++ errIf (!(opts ? cacheType) || (builtins.isString opts.cacheType && builtins.elem opts.cacheType validCacheTypes)) "model '${name}': 'options.cacheType' must be one of ${builtins.toString validCacheTypes}"
      ++ errIf (!(opts ? cacheTypeK) || (builtins.isString opts.cacheTypeK && builtins.elem opts.cacheTypeK validCacheTypes)) "model '${name}': 'options.cacheTypeK' must be one of ${builtins.toString validCacheTypes}"
      ++ errIf (!(opts ? cacheTypeV) || (builtins.isString opts.cacheTypeV && builtins.elem opts.cacheTypeV validCacheTypes)) "model '${name}': 'options.cacheTypeV' must be one of ${builtins.toString validCacheTypes}"
      ++ errIf (!(opts ? cacheType) || (!(opts ? cacheTypeK) && !(opts ? cacheTypeV))) "model '${name}': 'options.cacheType' shorthand cannot be combined with explicit 'cacheTypeK'/'cacheTypeV'"
      ++ errIf (!(opts ? reasoningBudget) || opts.reasoningBudget == null || (builtins.isInt opts.reasoningBudget && opts.reasoningBudget >= -1)) "model '${name}': 'options.reasoningBudget' must be an integer >= -1 (-1 = unrestricted) or null (server default)"
      ++ errIf (!(opts ? ttl) || (builtins.isInt opts.ttl && opts.ttl >= 0)) "model '${name}': 'options.ttl' must be a non-negative integer (0 = never evict)"
      ++ (
        if opts ? mtpProfile
        then checkMtpProfile name opts.mtpProfile
        else []
      )
      ++ errIf (!(opts ? extraArgs) || (builtins.isList opts.extraArgs && builtins.all builtins.isString opts.extraArgs)) "model '${name}': 'options.extraArgs' must be a list of strings"
      ++ errIf (!(opts ? templateOverride) || builtins.isString opts.templateOverride) "model '${name}': 'options.templateOverride' must be a string";

  checkEntry = name: entry:
    if !builtins.isAttrs entry
    then ["model '${name}': entry must be an object"]
    else
      errIf (entry ? displayName && builtins.isString entry.displayName) "model '${name}': 'displayName' is required and must be a string"
      ++ errIf (entry ? hfRef && builtins.isString entry.hfRef && builtins.match ".+/.+:.+" entry.hfRef != null) "model '${name}': 'hfRef' is required, must be a string like \"owner/repo:quant\""
      ++ (
        if entry ? options
        then checkOptions name entry.options
        else []
      );

  registryErrors =
    if !registryParse.success
    then ["models.json: invalid JSON"]
    else let
      reg = registryParse.value;
    in
      if !builtins.isAttrs reg
      then ["models.json: top level must be an object"]
      else
        errIf (reg ? default && builtins.isAttrs reg.default && (reg.default ? provider) && builtins.isString reg.default.provider && (reg.default ? name) && builtins.isString reg.default.name) "models.json: 'default' must be an object with string 'provider' and 'name'"
        ++ (let
          local = reg."llama.cpp" or null;
        in
          if !builtins.isAttrs local
          then ["models.json: 'llama.cpp' must be an object"]
          else lib.concatLists (lib.mapAttrsToList checkEntry local))
        ++ (let
          cloud = reg.opencode or null;
        in
          if !builtins.isAttrs cloud
          then ["models.json: 'opencode' must be an object"]
          else lib.concatLists (lib.mapAttrsToList (n: v: errIf (builtins.isString v) "cloud model '${n}': value must be a string") cloud))
        ++ (
          if !(reg ? default && builtins.isAttrs reg.default && (reg.default ? provider) && builtins.isString reg.default.provider && (reg.default ? name) && builtins.isString reg.default.name)
          then []
          else let
            p = reg.default.provider;
            n = reg.default.name;
            section = reg.${p} or null;
          in
            errIf (builtins.isAttrs section && builtins.hasAttr n section) "models.json: default model '${p}/${n}' is not registered"
        );

  # Opencode config generation (ticket #36): the provider block is derived
  # from the canonical registry. models.json stays the single source of
  # truth; opencode.json is never hand-edited.
  registry =
    if registryParse.success && builtins.isAttrs registryParse.value
    then registryParse.value
    else {};
  localModels = let
    section = registry."llama.cpp" or null;
  in
    if builtins.isAttrs section
    then section
    else {};

  validDefault =
    registry ? default && builtins.isAttrs registry.default && (registry.default ? provider) && builtins.isString registry.default.provider && (registry.default ? name) && builtins.isString registry.default.name;

  defaultRef =
    if validDefault
    then "${registry.default.provider}/${registry.default.name}"
    else "llama.cpp/qwen3-8b";

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

  # Swap config generation (ticket #37): per-model llama-server commands are
  # derived from the same registry options. models.json stays the single
  # source of truth; the hand-maintained swap config is retired.
  mkRegistryOpts = entry:
    if entry ? options && builtins.isAttrs entry.options
    then entry.options
    else {};
  swapCmd = name: entry: let
    opts = mkRegistryOpts entry;
    hfRef =
      if (entry ? hfRef) && builtins.isString entry.hfRef
      then entry.hfRef
      else name;
    ctxSize =
      if (opts ? ctxSize) && builtins.isInt opts.ctxSize && opts.ctxSize > 0
      then toString opts.ctxSize
      else "65536";
    cacheTypeK =
      if (opts ? cacheTypeK) && builtins.isString opts.cacheTypeK
      then opts.cacheTypeK
      else if (opts ? cacheType) && builtins.isString opts.cacheType
      then opts.cacheType
      else "f16";
    cacheTypeV =
      if (opts ? cacheTypeV) && builtins.isString opts.cacheTypeV
      then opts.cacheTypeV
      else if (opts ? cacheType) && builtins.isString opts.cacheType
      then opts.cacheType
      else "f16";
    gpuLayers =
      if !((opts ? gpuLayers) && builtins.isInt opts.gpuLayers)
      then "auto"
      else if opts.gpuLayers < 0
      then "all"
      else toString opts.gpuLayers;
    reasoningArgs =
      if !(opts ? reasoningBudget) || opts.reasoningBudget == null
      then []
      else ["--reasoning-budget" (toString opts.reasoningBudget)];
    templateArgs =
      if (opts ? templateOverride) && builtins.isString opts.templateOverride
      then ["--chat-template-file" opts.templateOverride]
      else [];
    # MTP flag names per llama.cpp speculative docs; re-verify when MTP
    # tuning lands (deferred post-spec). All current entries disable MTP.
    mtpProfile =
      if (opts ? mtpProfile) && builtins.isAttrs opts.mtpProfile
      then opts.mtpProfile
      else {};
    mtpArgs =
      if (mtpProfile ? enabled) && mtpProfile.enabled == true
      then
        [
          "--spec-type"
          (
            if (mtpProfile ? specType) && builtins.isString mtpProfile.specType
            then mtpProfile.specType
            else "draft-mtp"
          )
        ]
        ++ lib.optional ((mtpProfile ? draftModel) && builtins.isString mtpProfile.draftModel) "--model-draft"
        ++ lib.optional ((mtpProfile ? draftModel) && builtins.isString mtpProfile.draftModel) mtpProfile.draftModel
        ++ lib.optional ((mtpProfile ? draftTokensMax) && builtins.isInt mtpProfile.draftTokensMax) "--spec-draft-n-max"
        ++ lib.optional ((mtpProfile ? draftTokensMax) && builtins.isInt mtpProfile.draftTokensMax) (toString mtpProfile.draftTokensMax)
        ++ lib.optional ((mtpProfile ? draftCtxSize) && builtins.isInt mtpProfile.draftCtxSize) "--ctx-size-draft"
        ++ lib.optional ((mtpProfile ? draftCtxSize) && builtins.isInt mtpProfile.draftCtxSize) (toString mtpProfile.draftCtxSize)
        ++ lib.optional ((mtpProfile ? draftCacheTypeK) && builtins.isString mtpProfile.draftCacheTypeK) "--cache-type-k-draft"
        ++ lib.optional ((mtpProfile ? draftCacheTypeK) && builtins.isString mtpProfile.draftCacheTypeK) mtpProfile.draftCacheTypeK
        ++ lib.optional ((mtpProfile ? draftCacheTypeV) && builtins.isString mtpProfile.draftCacheTypeV) "--cache-type-v-draft"
        ++ lib.optional ((mtpProfile ? draftCacheTypeV) && builtins.isString mtpProfile.draftCacheTypeV) mtpProfile.draftCacheTypeV
      else [];
    extraArgs =
      if (opts ? extraArgs) && builtins.isList opts.extraArgs
      then opts.extraArgs
      else [];
  in
    lib.concatStringsSep " " ([
        "${pkgs.llama-cpp}/bin/llama-server"
        "--port"
        "\${PORT}"
        "-hf"
        hfRef
        "--jinja"
        "--ctx-size"
        ctxSize
        "--cache-type-k"
        cacheTypeK
        "--cache-type-v"
        cacheTypeV
        "--gpu-layers"
        gpuLayers
      ]
      ++ reasoningArgs
      ++ templateArgs
      ++ mtpArgs
      ++ extraArgs);

  swapModels =
    builtins.mapAttrs
    (name: entry: let
      opts = mkRegistryOpts entry;
    in {
      checkEndpoint = "/health";
      cmd = swapCmd name entry;
      ttl =
        if (opts ? ttl) && builtins.isInt opts.ttl && opts.ttl >= 0
        then opts.ttl
        else 120;
    })
    localModels;

  # Explicit one-resident group (map decision): exactly one local model
  # resident at a time. llama-swap's implicit default is identical; this
  # states it for audit.
  swapConfig = {
    healthCheckTimeout = 300;
    globalTTL = 0;
    routing = {
      router = {
        use = "group";
        settings = {
          groups = {
            local-llms = {
              swap = true;
              exclusive = true;
              members = builtins.attrNames localModels;
            };
          };
        };
      };
    };
    models = swapModels;
  };

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
      "llama.cpp" = {
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

  swapConfigPath = "${config.home.homeDirectory}/.config/llama-swap/config.yaml";

  # API keys live in a gitignored env dir and must never reach the Nix store,
  # so they are sourced into the login session at runtime rather than declared
  # as session variables. opencode-desktop imports the login-shell environment,
  # so both front-ends see them.
  envScript = pkgs.writeShellScript "source-llm-agent-env" ''
    if [ -d "${envDir}" ]; then
      for env_file in "${envDir}"/*.env; do
        [ -e "$env_file" ] || continue
        set -a
        . "$env_file"
        set +a
      done
      unset env_file
    fi
  '';
 in {
   home.packages = [
     pkgs.llama-cpp
     pkgs.llama-swap
     pkgs.opencode
     pkgs.opencode-desktop
     pkgs.opencode-claude-auth
   ];

   # The backend is always on (ADR 0001). It costs ~10 MB and a listening
   # socket; the resource that matters is the resident model, which is managed
   # separately. Making it unconditional is what lets opencode-desktop select a
   # local model at all — it forks a bundled sidecar and never executes anything
   # from PATH, so a demand-start wrapper could never be triggered by it.
   systemd.user.services.llama-swap = {
     Unit = {
       Description = "llama-swap backend for local models";
       After = [ "network-online.target" ];
       Wants = [ "network-online.target" ];
     };
     Service = {
       Type = "exec";
       ExecStart = "${pkgs.llama-swap}/bin/llama-swap -config ${swapConfigPath} -listen ${llamaHost}:${llamaPort}";
       Restart = "on-failure";
       RestartSec = "2s";
     };
     Install.WantedBy = [ "default.target" ];
   };

  programs.bash.profileExtra = lib.mkAfter ''
    [ -f "${envScript}" ] && . "${envScript}"
  '';

  home.file.".config/opencode/opencode.json".text = builtins.toJSON opencodeConfig;
  home.file.".config/opencode/AGENTS.md".source = ./AGENTS.md;
  # The hand-maintained swap config is retired; backupFileExtension keeps a
  # reversible copy of the existing file on first deploy.
  home.file.".config/llama-swap/config.yaml".text = builtins.toJSON swapConfig;

  assertions =
    map
    (message: {
      assertion = false;
      message = "llm-agent ${message}";
    })
    registryErrors
    ++ lib.optional (llamaHost != "127.0.0.1") "llamaHost must be a loopback address: the backend has no authentication";
}
