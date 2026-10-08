{
  pkgs,
  lib,
  llamaHost,
  llamaPort,
  envDir,
  homeDirectory,
  localModels,
  errIf,
}: let
  # Swap config generation (ticket #37): per-model llama-server commands are
  # derived from the same registry options. The split registry (config.json +
  # models/<key>.json) is the single source of truth; the hand-maintained swap
  # config is retired.
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
    # Server-side sampling baseline. opencode sends no sampling params for
    # these custom models, so the CLI flags are the effective defaults; an
    # agent-level temperature still overrides per session.
    samplingArgs =
      lib.optionals ((opts ? temperature) && (builtins.isFloat opts.temperature || builtins.isInt opts.temperature)) ["--temperature" (toString opts.temperature)]
      ++ lib.optionals ((opts ? topP) && (builtins.isFloat opts.topP || builtins.isInt opts.topP)) ["--top-p" (toString opts.topP)]
      ++ lib.optionals ((opts ? topK) && builtins.isInt opts.topK) ["--top-k" (toString opts.topK)]
      ++ lib.optionals ((opts ? minP) && (builtins.isFloat opts.minP || builtins.isInt opts.minP)) ["--min-p" (toString opts.minP)];
    # Speculative decoding flags per the llama.cpp server docs (v0.5.0).
    # specProfile covers every --spec-type, not just MTP.
    specProfile =
      if (opts ? specProfile) && builtins.isAttrs opts.specProfile
      then opts.specProfile
      else {};
    specArgs =
      if (specProfile ? enabled) && specProfile.enabled == true
      then
        [
          "--spec-type"
          (
            if (specProfile ? specType) && builtins.isString specProfile.specType
            then specProfile.specType
            else "draft-mtp"
          )
        ]
        ++ lib.optional ((specProfile ? draftModel) && builtins.isString specProfile.draftModel) "--model-draft"
        ++ lib.optional ((specProfile ? draftModel) && builtins.isString specProfile.draftModel) specProfile.draftModel
        ++ lib.optional ((specProfile ? draftTokensMax) && builtins.isInt specProfile.draftTokensMax) "--spec-draft-n-max"
        ++ lib.optional ((specProfile ? draftTokensMax) && builtins.isInt specProfile.draftTokensMax) (toString specProfile.draftTokensMax)
        ++ lib.optional ((specProfile ? draftPMin) && (builtins.isFloat specProfile.draftPMin || builtins.isInt specProfile.draftPMin)) "--spec-draft-p-min"
        ++ lib.optional ((specProfile ? draftPMin) && (builtins.isFloat specProfile.draftPMin || builtins.isInt specProfile.draftPMin)) (toString specProfile.draftPMin)
        ++ lib.optional ((specProfile ? draftPSplit) && (builtins.isFloat specProfile.draftPSplit || builtins.isInt specProfile.draftPSplit)) "--spec-draft-p-split"
        ++ lib.optional ((specProfile ? draftPSplit) && (builtins.isFloat specProfile.draftPSplit || builtins.isInt specProfile.draftPSplit)) (toString specProfile.draftPSplit)
        ++ (
          if specProfile ? draftGpuLayers
          then
            if builtins.isString specProfile.draftGpuLayers
            then ["--spec-draft-ngl" specProfile.draftGpuLayers]
            else [
              "--spec-draft-ngl"
              (
                if specProfile.draftGpuLayers < 0
                then "all"
                else toString specProfile.draftGpuLayers
              )
            ]
          else []
        )
        ++ lib.optional ((specProfile ? draftCacheTypeK) && builtins.isString specProfile.draftCacheTypeK) "--cache-type-k-draft"
        ++ lib.optional ((specProfile ? draftCacheTypeK) && builtins.isString specProfile.draftCacheTypeK) specProfile.draftCacheTypeK
        ++ lib.optional ((specProfile ? draftCacheTypeV) && builtins.isString specProfile.draftCacheTypeV) "--cache-type-v-draft"
        ++ lib.optional ((specProfile ? draftCacheTypeV) && builtins.isString specProfile.draftCacheTypeV) specProfile.draftCacheTypeV
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
      ++ samplingArgs
      ++ specArgs
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

  swapConfigPath = "${homeDirectory}/.config/llama-swap/config.yaml";

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
  loopbackHosts = ["127.0.0.1" "localhost" "::1" "[::1]"];
  backendError =
    lib.optional (!(builtins.elem llamaHost loopbackHosts))
    "llamaHost must be a loopback address: the backend has no authentication";

  # Fail loudly if something else already owns the port, rather than letting the
  # unit crash-loop on a bind error.
  preflight = pkgs.writeShellScript "llama-swap-preflight" ''
    if ${pkgs.procps}/bin/pgrep -f "(^|/)llama-swap( |$)" >/dev/null 2>&1; then
      echo "llama-swap is already running; stop it before starting the service." >&2
      ${pkgs.procps}/bin/pgrep -af "(^|/)llama-swap( |$)" >&2 || true
      exit 1
    fi
  '';

  # Unloads the resident model before the host suspends. There is no
  # sleep.target in the user manager, so this holds a `sleep` delay lock and
  # listens for logind's PrepareForSleep on the system bus: the lock gives the
  # unload up to InhibitDelayMaxSec (default 5 s) to finish, and watching the
  # signal without the lock is racy. Documented in
  # docs/llm-agent/llama-server-shutdown.md.
  #
  # The lock is released right after the unload (instead of held across the
  # suspend) so the host sleeps at once rather than waiting out the full
  # delay, and re-taken on resume to re-arm the next cycle. The inhibitor runs
  # detached (setsid) so one group kill takes both it and its `sleep` child
  # down; a plain kill would orphan the sleeper once per cycle.
  sleepGuard = pkgs.writeShellScript "llama-swap-sleep-guard" ''
    shopt -s lastpipe
    set -euo pipefail
    BACKEND="http://${llamaHost}:${llamaPort}"

    unload() {
      ${pkgs.curl}/bin/curl -fsS -X POST --max-time 10 "$BACKEND/api/models/unload" >/dev/null 2>&1 || true
    }

    inhibitor_pid=""
    start_inhibitor() {
      ${pkgs.util-linux}/bin/setsid ${pkgs.systemd}/bin/systemd-inhibit \
        --what=sleep \
        --mode=delay \
        --who="llama-swap-sleep-guard" \
        --why="Unload resident model before suspend" \
        ${pkgs.coreutils}/bin/sleep infinity &
      inhibitor_pid=$!
    }
    stop_inhibitor() {
      if [[ -n "$inhibitor_pid" ]]; then
        kill -- -"$inhibitor_pid" 2>/dev/null || true
        wait "$inhibitor_pid" 2>/dev/null || true
      fi
      inhibitor_pid=""
    }
    cleanup() { stop_inhibitor; }
    # A trapped TERM does not end the script on its own — without the explicit
    # exit the loop would go back to blocking on read. 143 is the conventional
    # "killed by SIGTERM" status, so an unexpected kill still trips
    # Restart=on-failure while an explicit `systemctl stop` stays a clean stop.
    trap cleanup EXIT
    trap 'cleanup; exit 143' TERM INT

    start_inhibitor

    # dbus-monitor prints the PrepareForSleep argument as `boolean true/false`
    # on its own line. The match rule selects only that signal, so any boolean
    # seen here is the suspend/resume flag.
    ${pkgs.dbus}/bin/dbus-monitor \
      --system "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" 2>/dev/null |
    while read -r line; do
      case "$line" in
        *"boolean true"*)
          # Suspending. Unload first (curl blocks until the server is stopped),
          # then release the delay lock so suspend proceeds at once.
          unload
          stop_inhibitor
          ;;
        *"boolean false"*)
          # Resumed. Re-take the lock unless it is still held.
          if [[ -z "$inhibitor_pid" ]] || ! kill -0 "$inhibitor_pid" 2>/dev/null; then
            start_inhibitor
          fi
          ;;
      esac
    done
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
  inherit
    swapConfig
    swapConfigPath
    preflight
    sleepGuard
    envActivation
    generatedConfigErrors
    backendError
    ;

  # The backend is always on (ADR 0001). It costs ~10 MB and a listening
  # socket; the resource that matters is the resident model, which is managed
  # separately. Making it unconditional is what lets opencode-desktop select a
  # local model at all — it forks a bundled sidecar and never executes anything
  # from PATH, so a demand-start wrapper could never be triggered by it.
  services = {
    llama-swap = {
      Unit = {
        Description = "llama-swap backend for local models";
        After = ["network-online.target"];
        Wants = ["network-online.target"];
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
      Install.WantedBy = ["default.target"];
    };

    # Unloads the resident model before suspend (see the sleepGuard script
    # above). The backend itself stays up across sleep; only the resident
    # model is released. Independent of the backend unit — an unload against a
    # down backend is a harmless no-op — and ordered after it so a fresh boot
    # arms the guard once the endpoint exists.
    llama-swap-sleep-guard = {
      Unit = {
        Description = "Unload resident llama-server before host suspend";
        After = ["llama-swap.service"];
      };
      Service = {
        Type = "exec";
        ExecStart = "${sleepGuard}";
        Restart = "on-failure";
        RestartSec = "2s";
      };
      Install.WantedBy = ["default.target"];
    };
  };

  # environment.d is read when the user manager starts, so the new values only
  # reach units started after the reload. Restarting the manager is what makes
  # them visible to GUI apps launched afterwards.
  #
  # The always-on llama-swap backend keeps its model registry in memory from
  # startup, and a registry-only deploy leaves its unit file byte-identical,
  # so systemd never restarts it on its own: new model IDs would 404 as
  # "model not found" until a manual restart. Restarting here — after the new
  # config.yaml is on disk and the manager has re-read environment.d — makes
  # every `config build` pick up the registry. When the user manager is
  # unreachable (a deploy outside a user session) the restart is skipped with
  # a warning; the service then picks the new config up at the next session
  # start. A restart failure with the manager reachable fails the deploy: a
  # stale backend after a registry change is the bug this exists to prevent.
  #
  # The activation script runs in a login shell whose PATH is the user
  # profile's, not the unit's Environment= PATH, and /run/current-system may
  # be mid-switch — so `systemctl` is addressed by store path (the same
  # pattern home-manager's own generated units use) and XDG_RUNTIME_DIR is
  # set explicitly: the wrapper's best-effort session import uses bare
  # `systemctl` too and fails the same way, leaving no bus address behind.
  activation = lib.hm.dag.entryAfter ["home-manager-files"] ''
    install -Dm600 ${envActivation} "$HOME/.config/environment.d/.llm-agent-activation"
    HOME="$HOME" ${envActivation}
    if [ -z "$XDG_RUNTIME_DIR" ]; then XDG_RUNTIME_DIR="/run/user/$UID"; fi
    export XDG_RUNTIME_DIR
    ${pkgs.systemd}/bin/systemctl --user daemon-reload 2>/dev/null || true
    if out=$(${pkgs.systemd}/bin/systemctl --user restart llama-swap 2>&1); then
      :
    elif printf '%s' "$out" | grep -q "connect to.*bus"; then
      echo "llm-agent: user manager unreachable; llama-swap will pick up the new registry at session start" >&2
    else
      echo "llm-agent: failed to restart llama-swap after deploy: $out" >&2
      exit 1
    fi
    # The sleep guard carries no config — only store paths — so a missed
    # restart leaves a working guard behind. Warn, never fail the deploy.
    if out=$(${pkgs.systemd}/bin/systemctl --user restart llama-swap-sleep-guard 2>&1); then
      :
    else
      echo "llm-agent: could not restart llama-swap-sleep-guard: $out" >&2
    fi
  '';

  files = {
    ".config/llama-swap/config.yaml".text = builtins.toJSON swapConfig;
  };
}
