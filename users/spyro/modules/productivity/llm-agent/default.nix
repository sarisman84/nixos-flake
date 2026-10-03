{
  config,
  pkgs,
  lib,
  ...
}: let
  llamaHost = "127.0.0.1";
  llamaPort = "8080";
  envDir = "${config.home.homeDirectory}/config/nixos-flake/users/spyro/modules/productivity/llm-agent/env";

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
        )
        ++ (let
          policy = reg.unloadPolicy or null;
          positiveInt = v: builtins.isInt v && v > 0;
        in
          if !builtins.isAttrs policy
          then ["models.json: 'unloadPolicy' must be an object"]
          else
            # `errIf` reports when its condition is FALSE, so the expected shape
            # is passed whole: `(has field) && (field is valid)`. Spelling this
            # `!(has) || valid` — as checkOptions does — makes it a no-op for a
            # missing field, which is the case worth catching here.
            errIf ((policy ? idleThresholdSeconds) && positiveInt policy.idleThresholdSeconds) "models.json: 'unloadPolicy.idleThresholdSeconds' is required and must be a positive integer"
            ++ errIf ((policy ? settleSeconds) && positiveInt policy.settleSeconds) "models.json: 'unloadPolicy.settleSeconds' is required and must be a positive integer"
            ++ (map (f: "models.json: unknown unloadPolicy field '${f}'") (builtins.filter (f: !(builtins.elem f [ "idleThresholdSeconds" "settleSeconds" ])) (builtins.attrNames policy)))
        );

  # Opencode config generation (ticket #36): the provider block is derived
  # from the canonical registry. models.json stays the single source of
  # truth; opencode.json is never hand-edited.
  registry =
    if registryParse.success && builtins.isAttrs registryParse.value
    then registryParse.value
    else {};
  # The provider whose models the backend fronts. The plugin needs the name to
  # tell a local session from a cloud one, so it is generated rather than
  # hardcoded in TypeScript where it could drift from the registry.
  localProviderId = "llama.cpp";
  localModels = let
    section = registry.${localProviderId} or null;
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

  swapConfigPath = "${config.home.homeDirectory}/.config/llama-swap/config.yaml";

  # The backend is always on (ADR 0001), so the generated swap config is now
  # load-bearing rather than incidental. Asserting its shape means a future
  # edit that quietly drops the one-resident guarantee fails the build instead
  # of loading two models into 32 GB of VRAM at inference time.
  swapGroup = swapConfig.routing.router.settings.groups.local-llms;

  # `errIf` takes the *expected* shape and reports when it does not hold.
  generatedConfigErrors =
    errIf ((swapConfig ? globalTTL) && builtins.isInt swapConfig.globalTTL)
      "generated swap config must set an integer globalTTL"
    ++ errIf ((swapConfig ? models) && builtins.isAttrs swapConfig.models)
      "generated swap config must define models"
    ++ errIf ((builtins.attrNames (swapConfig.models or {})) == (builtins.attrNames localModels))
      "generated swap config models must match the registry entries exactly"
    ++ (
      if !builtins.isAttrs swapGroup
      then ["generated swap config is missing the 'local-llms' swap group"]
      else
        errIf ((swapGroup ? swap) && swapGroup.swap == true)
          "swap group 'local-llms' must set swap = true (one resident model at a time)"
        ++ errIf ((swapGroup ? exclusive) && swapGroup.exclusive == true)
          "swap group 'local-llms' must set exclusive = true"
        ++ errIf ((swapGroup ? members) && builtins.isList swapGroup.members && (builtins.sort builtins.lessThan swapGroup.members) == (builtins.sort builtins.lessThan (builtins.attrNames localModels)))
          "swap group 'local-llms' must list exactly the registry entries"
    );

  # An always-on backend with no authentication must never listen off-loopback.
  loopbackHosts = [ "127.0.0.1" "localhost" "::1" "[::1]" ];
  backendError = lib.optional (!(builtins.elem llamaHost loopbackHosts))
    "llamaHost must be a loopback address: the backend has no authentication";

  # The idle thresholds are registry data, not code constants (spec #34): the
  # plugin reads them from this generated file rather than hard-coding them, so
  # retuning is an edit to models.json.
  unloadPolicy = registry.unloadPolicy or {};
  # Read defensively: a malformed registry must surface as a readable
  # assertion below, not as `attribute 'idleThresholdSeconds' missing` from
  # whichever consumer happens to force this value first.
  unloadPolicyConfig = {
    idleThresholdSeconds = unloadPolicy.idleThresholdSeconds or null;
    settleSeconds = unloadPolicy.settleSeconds or null;
    backend = "http://${llamaHost}:${llamaPort}";
    localProviderId = localProviderId;
  };

  # The plugin is deployed as ONE self-contained file in opencode's plugin
  # directory, built by splicing `decision.ts` and `plugin.ts` together.
  #
  # This is not a stylistic choice. `home.file.<name>.text` compiles each file
  # to its OWN store path, named after the target with separators stripped, not
  # a directory tree. So a relative import from a deployed file resolves against
  # the Nix store: an entry that re-exported `../llm-agent/plugin.js` looked for
  # it beside itself in /nix/store, failed, and — because the loader discards
  # the cause of a plugin load failure — the only symptom was a missing
  # heartbeat. The deployed copy has to stand alone.
  #
  # The seam is still authored and tested as its own module; only the deployed
  # artefact is a concatenation. The splice removes plugin.ts's import of the
  # seam and asserts it was actually removed, so reformatting plugin.ts cannot
  # silently leave a dead import behind (which would fail the same silent way).
  decisionSource = builtins.readFile ./policy/decision.ts;
  pluginSource = builtins.readFile ./policy/plugin.ts;

  # The exact import block, asserted below so a reformat cannot invalidate it.
  seamImport = ''
    import {
      isRepeatUnload,
      shouldUnload,
      type Decision,
      type InflightEntry,
      type Lease,
      type LeaseSet,
    } from "./decision.js"
  '';
  pluginWithoutSeamImport = builtins.replaceStrings [ "
${seamImport}" ] [ "
" ] pluginSource;

  pluginEntry = ''
    // Generated by nixos-flake. Edit policy/decision.ts or policy/plugin.ts,
    // never this file: it is their concatenation.
    ${decisionSource}
    ${pluginWithoutSeamImport}
  '';


  # Assert the *generated* file, not the registry it came from: the registry is
  # already validated above, and what the plugin actually reads is this file. A
  # broken derivation between the two is the failure worth catching.
  policyErrors =
    errIf (builtins.isInt unloadPolicyConfig.idleThresholdSeconds && unloadPolicyConfig.idleThresholdSeconds > 0)
      "generated unload policy must carry a positive integer idle threshold"
    ++ errIf (builtins.isInt unloadPolicyConfig.settleSeconds && unloadPolicyConfig.settleSeconds > 0)
      "generated unload policy must carry a positive integer settle delay"
    ++ errIf (builtins.isString unloadPolicyConfig.backend && builtins.match "http://(127\.0\.0\.1|localhost|\[::1\]):[0-9]+" unloadPolicyConfig.backend != null)
      "generated unload policy must point the plugin at a loopback backend"
    ++ errIf (unloadPolicyConfig.localProviderId == localProviderId)
      "generated unload policy must name the registry's local provider, so the plugin and the registry cannot disagree about what is local"
    # `errIf` reports when its condition is FALSE, so "must not contain" is
    # spelled as the *absence* being the passing case.
    ++ errIf (!(lib.hasInfix "decision.js" pluginEntry))
      "the deployed plugin must not reference ./decision.js: it is spliced in, and a live import would resolve against the Nix store and fail to load silently"
    ++ errIf (pluginWithoutSeamImport != pluginSource)
      "the deployed plugin must still contain plugin.ts's source: the seam import it strips was reformatted, so the splice is no longer sound"
    ++ errIf (lib.hasInfix "function shouldUnload" pluginEntry && lib.hasInfix "LlmAgentUnloadPolicy" pluginEntry)
      "the deployed plugin must carry both the decision seam and the plugin entry";


  # API keys live in a gitignored env dir and must never reach the Nix store,
  # so they are rendered at activation time into ~/.config/environment.d/,
  # which the systemd user manager reads for every unit it starts — including
  # the opencode-desktop sidecar, which is launched by the desktop session
  # rather than from a login shell. A profile hook alone would reach the CLI
  # but not the desktop app, which is the one front-end that cannot be relied
  # on to inherit from a shell.
  # Fail loudly if something else already owns the port, rather than letting the
  # unit crash-loop on a bind error.
  preflight = pkgs.writeShellScript "llama-swap-preflight" ''
    if ${pkgs.procps}/bin/pgrep -f "(^|/)llama-swap( |$)" >/dev/null 2>&1; then
      echo "llama-swap is already running; stop it before starting the service." >&2
      ${pkgs.procps}/bin/pgrep -af "(^|/)llama-swap( |$)" >&2 || true
      exit 1
    fi
  '';

  envActivation = pkgs.writeShellScript "llm-agent-env-activation" ''
    target="$HOME/.config/environment.d/50-llm-agent.conf"
    mkdir -p "$(dirname "$target")"
    if [ -d "${envDir}" ]; then
      cat "${envDir}"/*.env >"$target" 2>/dev/null || : >"$target"
    else
      : >"$target"
    fi
    chmod 600 "$target"
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
      # A llama-swap left over from the demand-start era would hold the port
      # and make this unit crash-loop forever. Fail once with a clear message
      # instead of retrying silently.
      ExecStartPre = "${preflight}";
      ExecStart = "${pkgs.llama-swap}/bin/llama-swap -config ${swapConfigPath} -listen ${llamaHost}:${llamaPort}";
      Restart = "on-failure";
      RestartSec = "2s";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # environment.d is read when the user manager starts, so the new values only
  # reach units started after the reload. Restarting the manager is what makes
  # them visible to GUI apps launched afterwards.
  home.activation.llamaAgentEnv = lib.hm.dag.entryAfter [ "home-manager-files" ] ''
    install -Dm600 ${envActivation} "$HOME/.config/environment.d/.llm-agent-activation"
    HOME="$HOME" ${envActivation}
    systemctl --user daemon-reload 2>/dev/null || true
  '';

  home.file.".config/opencode/opencode.json".text = builtins.toJSON opencodeConfig;
  home.file.".config/opencode/AGENTS.md".source = ./AGENTS.md;
  home.file.".config/llama-swap/config.yaml".text = builtins.toJSON swapConfig;
  home.file.".config/llama-swap/unload-policy.json".text = builtins.toJSON unloadPolicyConfig;

  home.file.".config/opencode/plugins/llm-agent-unload.ts".text = pluginEntry;

  assertions =
    map
    (message: {
      assertion = false;
      message = "llm-agent ${message}";
    })
    (registryErrors ++ generatedConfigErrors ++ backendError ++ policyErrors)
    ++ (lib.optional (!(config.systemd.user.services ? llama-swap)) {
      assertion = false;
      message = "llm-agent the always-on llama-swap service must be defined";
    });
}
