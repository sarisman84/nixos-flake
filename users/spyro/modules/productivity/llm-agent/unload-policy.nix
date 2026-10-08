{
  registry,
  llamaHost,
  llamaPort,
  localProviderId,
  errIf,
}: let
  # The idle thresholds are registry data, not code constants (spec #34): the
  # plugin reads them from this generated file rather than hard-coding them, so
  # retuning is an edit to config.json's `unloadPolicy`.
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
    "generated unload policy must name the registry's local provider, so the plugin and the registry cannot disagree about what is local";
in {
  inherit
    unloadPolicyConfig
    policyErrors
    ;
  files = {
    ".config/llama-swap/unload-policy.json".text = builtins.toJSON unloadPolicyConfig;
  };
}
