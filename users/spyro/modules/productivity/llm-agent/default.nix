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
  validOptionFields = ["ctxSize" "gpuLayers" "cacheType" "cacheTypeK" "cacheTypeV" "reasoningBudget" "ttl" "mtpProfile" "extraArgs" "templateOverride"];
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

  wrapperScript = builtins.readFile ./opencode-wrapper.sh;
  opencodeWrapper = pkgs.writeShellScriptBin "opencode" (
    lib.replaceStrings
    [
      "__env_dir__"
      "__curl_bin__"
      "__llama_bin__"
      "__opencode_bin__"
      "__llama_health_url__"
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
      llamaHost
      llamaPort
      modelsJson
      "${pkgs.jq}/bin/jq"
    ]
    wrapperScript
  );
in {
  home.packages = [
    pkgs.llama-cpp
    pkgs.llama-swap
    opencodeWrapper
    pkgs.opencode-desktop
    pkgs.opencode-claude-auth
  ];

  home.file.".config/opencode/opencode.json".source = ./opencode.json;
  home.file.".config/opencode/AGENTS.md".source = ./AGENTS.md;

  assertions =
    map
    (message: {
      assertion = false;
      message = "llm-agent ${message}";
    })
    registryErrors;
}
