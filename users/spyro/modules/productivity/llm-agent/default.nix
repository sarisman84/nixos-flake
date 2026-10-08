{
  config,
  pkgs,
  lib,
  ...
}: let
  # The registry is the single source of truth: it loads and validates
  # config.json, cloud-models.json, and models/<key>.json, and derives the
  # values every concern below consumes. Each concern file is a plain function
  # (imported, not module-imported) that takes the registry context and returns
  # its generated artefacts, files, and assertions.
  registry = import ./registry.nix {
    inherit lib;
    homeDirectory = config.home.homeDirectory;
  };

  opencode = import ./opencode.nix {
    inherit (registry) registry localModels localProviderId defaultRef;
  };

  llamaSwap = import ./llama-swap.nix {
    inherit pkgs lib;
    inherit (registry) llamaHost llamaPort envDir localModels errIf;
    homeDirectory = config.home.homeDirectory;
  };

  unloadPolicy = import ./unload-policy.nix {
    inherit (registry) registry llamaHost llamaPort localProviderId errIf;
  };

  plugin = import ./plugin.nix {
    inherit lib;
    inherit (registry) errIf;
  };
in {
  home.packages = [
    pkgs.llama-cpp
    pkgs.llama-swap
    pkgs.opencode
    pkgs.opencode-desktop
    pkgs.opencode-claude-auth
  ];

  systemd.user.services = llamaSwap.services;

  home.activation.llamaAgentEnv = llamaSwap.activation;

  home.file =
    opencode.files
    // llamaSwap.files
    // unloadPolicy.files
    // plugin.files;

  assertions =
    map
    (message: {
      assertion = false;
      message = "llm-agent ${message}";
    })
    (registry.topJsonErrors
      ++ registry.modelListErrors
      ++ registry.modelFileErrors
      ++ registry.duplicateModelErrors
      ++ registry.registryErrors
      ++ llamaSwap.generatedConfigErrors
      ++ llamaSwap.backendError
      ++ unloadPolicy.policyErrors ++ plugin.pluginErrors)
    ++ (lib.optional (!(config.systemd.user.services ? llama-swap)) {
      assertion = false;
      message = "llm-agent the always-on llama-swap service must be defined";
    })
    ++ (lib.optional (!(config.systemd.user.services ? llama-swap-sleep-guard)) {
      assertion = false;
      message = "llm-agent the suspend-time unload guard must be defined";
    });
}
