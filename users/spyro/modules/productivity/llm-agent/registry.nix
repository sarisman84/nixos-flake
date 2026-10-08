{
  lib,
  homeDirectory,
}: let
  llamaHost = "127.0.0.1";
  llamaPort = "8080";
  envDir = "${homeDirectory}/config/nixos-flake/users/spyro/modules/productivity/llm-agent/env";

  # The registry is split across files. `config.json` holds the global
  # settings (default model, unload policy) and the explicit list of model
  # entries to register; each listed entry `<key>` lives in `models/<key>.json`.
  # `cloud-models.json` maps cloud model aliases. A model is registered iff its
  # file is named in config.json; an unlisted file in models/ is ignored.
  # Malformed entries must fail `nix flake check` with a readable error,
  # surfaced through home-manager assertions.
  # Read a JSON file, degrading to null (and a readable error below) instead of
  # throwing, so a malformed file surfaces as an assertion, not an opaque eval
  # failure.
  readJson = path: builtins.tryEval (builtins.fromJSON (builtins.readFile path));
  globalConfigRes = readJson ./config.json;
  cloudModelsRes = readJson ./cloud-models.json;
  globalConfig =
    if globalConfigRes.success
    then globalConfigRes.value
    else {};
  cloudModels =
    if cloudModelsRes.success
    then cloudModelsRes.value
    else {};
  topJsonErrors =
    lib.optional (!globalConfigRes.success) "config.json: invalid JSON"
    ++ lib.optional (!cloudModelsRes.success) "cloud-models.json: invalid JSON";

  # The model files actually present, so "listed but missing" becomes a
  # readable error instead of a bare store-path open failure.
  modelFiles = builtins.readDir ./models;

  # The list of entries to register, from config.json. Coerced to a list so the
  # per-entry checks below total over a malformed value rather than throwing.
  modelList =
    if (globalConfig ? models) && builtins.isList globalConfig.models
    then globalConfig.models
    else [];

  # Per-file load. A listed entry whose file is absent, or whose file is not
  # valid JSON, is reported by name (below) and degraded to an empty entry so
  # the rest of the registry still evaluates and the real error surfaces as a
  # readable assertion instead of an opaque store-path throw.
  parseModelFile = name:
    if !(builtins.isString name) || !(modelFiles ? "${name}.json")
    then {
      name = name;
      missing = true;
      ok = false;
      value = null;
    }
    else let
      res = builtins.tryEval (builtins.fromJSON (builtins.readFile "${./models}/${name}.json"));
    in {
      name = name;
      missing = false;
      ok = res.success;
      value =
        if res.success
        then res.value
        else null;
    };

  parsedModelFiles = map parseModelFile modelList;

  # Readable errors for the model list and its files.
  modelListErrors =
    lib.optional (!((globalConfig ? models) && builtins.isList globalConfig.models)) "config.json: 'models' must be a list of model keys"
    ++ lib.concatLists (map (
        name:
          lib.optional (!(builtins.isString name)) "config.json: 'models' entries must be strings (got ${builtins.typeOf name})"
      )
      modelList);

  modelFileErrors = lib.concatLists (map (
      p:
        lib.optional (p.missing) "config.json: lists model '${toString p.name}' but models/${toString p.name}.json does not exist"
        ++ lib.optional (!p.missing && !p.ok) "models/${toString p.name}.json: invalid JSON"
    )
    parsedModelFiles);

  # Duplicate entries would make listToAttrs throw; report them readably.
  modelNames = map (p: toString p.name) (lib.filter (p: builtins.isString p.name) parsedModelFiles);
  duplicateModelErrors = let
    uniqueNames = lib.unique modelNames;
  in
    lib.optionals (builtins.length uniqueNames != builtins.length modelNames)
    (map (n: "config.json: model '${n}' is listed more than once")
      (lib.filter (n: builtins.length (lib.filter (m: m == n) modelNames) > 1) uniqueNames));

  # Register exactly the well-formed entries named in config.json. `name` is
  # the model key: the file name (minus .json) and the identity on the wire.
  localModelsFromFiles = lib.listToAttrs (
    map (p: {
      name = toString p.name;
      value = p.value or {};
    })
    (lib.filter (p: p.ok && builtins.isString p.name) parsedModelFiles)
  );

  # Combine all configuration. Guarded access so a malformed config.json
  # (degraded to {}) reports via the checks below rather than throwing here.
  # The key MUST be quoted: an unquoted `llama.cpp` attr name is parsed by Nix
  # as the key "llama" (truncated at the dot), which would not match the
  # quoted "llama.cpp" every consumer (registryErrors, localModels, the opencode
  # provider block) uses to look the section up.
  combinedRegistry = {
    default =
      if globalConfig ? default
      then globalConfig.default
      else {};
    unloadPolicy =
      if globalConfig ? unloadPolicy
      then globalConfig.unloadPolicy
      else {};
    "llama.cpp" = localModelsFromFiles;
    opencode = cloudModels;
  };

  # Validate registry
  registryParse = builtins.tryEval combinedRegistry;

  validCacheTypes = ["f32" "f16" "bf16" "q8_0" "q4_0" "q4_1" "iq4_nl" "q5_0" "q5_1"];
  validOptionFields = ["ctxSize" "outputLimit" "gpuLayers" "cacheType" "cacheTypeK" "cacheTypeV" "reasoningBudget" "ttl" "temperature" "topP" "topK" "minP" "specProfile" "extraArgs" "templateOverride"];
  validSpecFields = ["enabled" "specType" "draftModel" "draftTokensMax" "draftPMin" "draftPSplit" "draftGpuLayers" "draftCacheTypeK" "draftCacheTypeV"];
  # llama.cpp --spec-type list as of v0.5.0 (nixos-unstable). Re-verify on
  # `nix flake update`.
  validSpecTypes = ["none" "draft-simple" "draft-eagle3" "draft-mtp" "draft-dflash" "draft-dspark" "ngram-simple" "ngram-map-k" "ngram-map-k4v" "ngram-mod" "ngram-cache"];

  errIf = cond: msg: lib.optional (!cond) msg;

  validEntryFields = ["displayName" "hfRef" "options" "_comment"];

  checkSpecProfile = name: profile:
    if !builtins.isAttrs profile
    then ["model '${name}': 'options.specProfile' must be an object"]
    else let
      unknown = builtins.filter (f: !(builtins.elem f validSpecFields)) (builtins.attrNames profile);
    in
      (map (f: "model '${name}': unknown specProfile field '${f}'") unknown)
      ++ errIf (!(profile ? enabled) || builtins.isBool profile.enabled) "model '${name}': 'options.specProfile.enabled' must be a boolean"
      ++ errIf (!(profile ? specType) || (builtins.isString profile.specType && builtins.elem profile.specType validSpecTypes)) "model '${name}': 'options.specProfile.specType' must be one of ${builtins.toString validSpecTypes}"
      ++ errIf (!(profile ? draftModel) || builtins.isString profile.draftModel) "model '${name}': 'options.specProfile.draftModel' must be a string"
      ++ errIf (!(profile ? draftTokensMax) || (builtins.isInt profile.draftTokensMax && profile.draftTokensMax > 0)) "model '${name}': 'options.specProfile.draftTokensMax' must be a positive integer"
      ++ errIf (!(profile ? draftPMin) || ((builtins.isFloat profile.draftPMin || builtins.isInt profile.draftPMin) && profile.draftPMin >= 0 && profile.draftPMin <= 1)) "model '${name}': 'options.specProfile.draftPMin' must be a number in [0, 1]"
      ++ errIf (!(profile ? draftPSplit) || ((builtins.isFloat profile.draftPSplit || builtins.isInt profile.draftPSplit) && profile.draftPSplit >= 0 && profile.draftPSplit <= 1)) "model '${name}': 'options.specProfile.draftPSplit' must be a number in [0, 1]"
      ++ errIf (!(profile ? draftGpuLayers) || ((builtins.isInt profile.draftGpuLayers && profile.draftGpuLayers >= -1) || (builtins.isString profile.draftGpuLayers && builtins.elem profile.draftGpuLayers ["auto" "all"]))) "model '${name}': 'options.specProfile.draftGpuLayers' must be an integer >= -1 or 'auto'/'all'"
      ++ errIf (!(profile ? draftCacheTypeK) || (builtins.isString profile.draftCacheTypeK && builtins.elem profile.draftCacheTypeK validCacheTypes)) "model '${name}': 'options.specProfile.draftCacheTypeK' must be a KV cache type"
      ++ errIf (!(profile ? draftCacheTypeV) || (builtins.isString profile.draftCacheTypeV && builtins.elem profile.draftCacheTypeV validCacheTypes)) "model '${name}': 'options.specProfile.draftCacheTypeV' must be a KV cache type";

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
      ++ errIf (!(opts ? temperature) || ((builtins.isFloat opts.temperature || builtins.isInt opts.temperature) && opts.temperature >= 0)) "model '${name}': 'options.temperature' must be a number >= 0"
      ++ errIf (!(opts ? topP) || ((builtins.isFloat opts.topP || builtins.isInt opts.topP) && opts.topP >= 0 && opts.topP <= 1)) "model '${name}': 'options.topP' must be a number in [0, 1]"
      ++ errIf (!(opts ? topK) || (builtins.isInt opts.topK && opts.topK >= 0)) "model '${name}': 'options.topK' must be an integer >= 0 (0 = disabled)"
      ++ errIf (!(opts ? minP) || ((builtins.isFloat opts.minP || builtins.isInt opts.minP) && opts.minP >= 0 && opts.minP <= 1)) "model '${name}': 'options.minP' must be a number in [0, 1]"
      ++ (
        if opts ? specProfile
        then checkSpecProfile name opts.specProfile
        else []
      )
      ++ errIf (!(opts ? extraArgs) || (builtins.isList opts.extraArgs && builtins.all builtins.isString opts.extraArgs)) "model '${name}': 'options.extraArgs' must be a list of strings"
      ++ errIf (!(opts ? templateOverride) || builtins.isString opts.templateOverride) "model '${name}': 'options.templateOverride' must be a string";

  checkEntry = name: entry:
    if !builtins.isAttrs entry
    then ["model '${name}': entry must be an object"]
    else
      # `_comment` is documentation for a human reading models/<key>.json, and
      # is deliberately not a model field. Allowed here so an entry can explain
      # a constraint that the shape checks below cannot enforce.
      # `errIf` reports when the condition is FALSE, so the *expected* shape goes
      # in whole: absent is fine, present-but-not-a-string is not.
      errIf (!(entry ? _comment) || builtins.isString entry._comment)
      "model '${name}': '_comment', if present, must be a string"
      ++ (map (f: "model '${name}': unknown field '${f}'")
        (builtins.filter (f: !(builtins.elem f validEntryFields))
          (builtins.attrNames entry)))
      ++ errIf (entry ? displayName && builtins.isString entry.displayName) "model '${name}': 'displayName' is required and must be a string"
      ++ errIf (entry ? hfRef && builtins.isString entry.hfRef && builtins.match ".+/.+:.+" entry.hfRef != null) "model '${name}': 'hfRef' is required, must be a string like \"owner/repo:quant\""
      ++ (
        if entry ? options
        then checkOptions name entry.options
        else []
      );

  # Per-entry and global-shape validation over the combined registry. The
  # per-file JSON parse and the config.json/cloud-models.json reads are handled
  # by topJsonErrors / modelListErrors / modelFileErrors above; this block
  # checks the assembled shape (defaults, unload policy, registered entries).
  registryErrors =
    if !registryParse.success
    then ["registry: could not be assembled"]
    else let
      reg = registryParse.value;
    in
      if !builtins.isAttrs reg
      then ["registry: top level must be an object"]
      else
        errIf (reg ? default && builtins.isAttrs reg.default && (reg.default ? provider) && builtins.isString reg.default.provider && (reg.default ? name) && builtins.isString reg.default.name) "config.json: 'default' must be an object with string 'provider' and 'name'"
        ++ (let
          local = reg."llama.cpp" or null;
        in
          if !builtins.isAttrs local
          then ["registry: 'llama.cpp' must be an object"]
          else lib.concatLists (lib.mapAttrsToList checkEntry local))
        ++ (let
          cloud = reg.opencode or null;
        in
          if !builtins.isAttrs cloud
          then ["cloud-models.json: must be an object of model key -> value"]
          else lib.concatLists (lib.mapAttrsToList (n: v: errIf (builtins.isString v) "cloud model '${n}': value must be a string") cloud))
        ++ (
          if !(reg ? default && builtins.isAttrs reg.default && (reg.default ? provider) && builtins.isString reg.default.provider && (reg.default ? name) && builtins.isString reg.default.name)
          then []
          else let
            p = reg.default.provider;
            n = reg.default.name;
            section = reg.${p} or null;
          in
            errIf (builtins.isAttrs section && builtins.hasAttr n section) "config.json: default model '${p}/${n}' is not registered"
        )
        ++ (
          let
            policy = reg.unloadPolicy or null;
            positiveInt = v: builtins.isInt v && v > 0;
          in
            if !builtins.isAttrs policy
            then ["config.json: 'unloadPolicy' must be an object"]
            else
              # `errIf` reports when its condition is FALSE, so the expected shape
              # is passed whole: `(has field) && (field is valid)`. Spelling this
              # `!(has) || valid` — as checkOptions does — makes it a no-op for a
              # missing field, which is the case worth catching here.
              errIf ((policy ? idleThresholdSeconds) && positiveInt policy.idleThresholdSeconds) "config.json: 'unloadPolicy.idleThresholdSeconds' is required and must be a positive integer"
              ++ errIf ((policy ? settleSeconds) && positiveInt policy.settleSeconds) "config.json: 'unloadPolicy.settleSeconds' is required and must be a positive integer"
              ++ (map (f: "config.json: unknown unloadPolicy field '${f}'") (builtins.filter (f: !(builtins.elem f ["idleThresholdSeconds" "settleSeconds"])) (builtins.attrNames policy)))
        );

  # Opencode config generation (ticket #36): the provider block is derived
  # from the canonical registry. registry is the combined configuration from
  # config.json, cloud-models.json, and the individual models/<key>.json files.
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

  # Use localModelsFromFiles instead of localModels for model entries

  validDefault =
    registry ? default && builtins.isAttrs registry.default && (registry.default ? provider) && builtins.isString registry.default.provider && (registry.default ? name) && builtins.isString registry.default.name;

  defaultRef =
    if validDefault
    then "${registry.default.provider}/${registry.default.name}"
    else "llama.cpp/qwen3-8b";
in {
  inherit
    llamaHost
    llamaPort
    envDir
    errIf
    registry
    localProviderId
    localModels
    defaultRef
    topJsonErrors
    modelListErrors
    modelFileErrors
    duplicateModelErrors
    registryErrors
    ;
}
