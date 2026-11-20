/**
 * The three artefact generators, ported from the flake's Nix:
 *
 *   - `generateSwapConfig`      ← llama-swap.nix (`swapCmd` + `swapConfig`)
 *   - `generateOpencodeConfig`  ← opencode.nix (`opencodeConfig`)
 *   - `generateUnloadPolicy`    ← unload-policy.nix (`unloadPolicyConfig`)
 *
 * Each takes the validated single-file registry and produces the same object
 * the flake built at build time. `toNixJson` serializes with Nix `toJSON`
 * semantics (object keys sorted, floats to six decimals) so the output matches
 * the flake byte-for-byte.
 */
import { type Json, nixToString, NixNum } from "./json.js"
import { type ModelEntry, type Registry } from "./registry.js"

/**
 * Serialize with Nix `builtins.toJSON` semantics: object keys sorted
 * alphabetically, a `NixNum` rendered as a bare int or a six-decimal float.
 * This is what makes the generated artefacts match the flake's output exactly.
 */
export function toNixJson(value: unknown): string {
  return serialize(value)
}

function serialize(v: unknown): string {
  if (v === null) return "null"
  // Nix has no `undefined`; a generated object that carries one is a bug, so
  // fail loudly rather than silently emit `null` where the flake would not.
  if (v === undefined) throw new Error("toNixJson: undefined is not a Nix value")
  if (v instanceof NixNum) return v.isFloat ? v.value.toFixed(6) : String(v.value)
  if (typeof v === "string") return JSON.stringify(v)
  if (typeof v === "number") return Number.isInteger(v) ? String(v) : v.toFixed(6)
  if (typeof v === "boolean") return v ? "true" : "false"
  if (Array.isArray(v)) return `[${v.map(serialize).join(",")}]`
  if (typeof v === "object") {
    const keys = Object.keys(v as object).sort()
    const parts = keys.map(
      (k) => `${JSON.stringify(k)}:${serialize((v as Record<string, unknown>)[k])}`,
    )
    return `{${parts.join(",")}}`
  }
  throw new Error(`toNixJson: cannot serialize value of type ${typeof v}`)
}

// --- config.yaml (llama-swap) -------------------------------------------------

/** The per-model `llama-server` argv, ported from `swapCmd` in llama-swap.nix. */
function swapCmd(name: string, entry: ModelEntry, llamaServerPath: string): string {
  const opts = entry.options ?? {}
  const hfRef = entry.hfRef ?? name
  const ctxSize =
    opts.ctxSize && opts.ctxSize.value > 0 ? nixToString(opts.ctxSize) : "65536"
  const cacheTypeK =
    opts.cacheTypeK ?? opts.cacheType ?? "f16"
  const cacheTypeV =
    opts.cacheTypeV ?? opts.cacheType ?? "f16"
  const gpuLayers =
    !opts.gpuLayers
      ? "auto"
      : opts.gpuLayers.value < 0
        ? "all"
        : String(opts.gpuLayers.value)

  const reasoningArgs: string[] =
    opts.reasoningBudget === undefined || opts.reasoningBudget === null
      ? []
      : ["--reasoning-budget", nixToString(opts.reasoningBudget)]

  const templateArgs: string[] =
    opts.templateOverride !== undefined ? ["--chat-template-file", opts.templateOverride] : []

  const samplingArgs: string[] = [
    ...(opts.temperature !== undefined ? ["--temperature", nixToString(opts.temperature)] : []),
    ...(opts.topP !== undefined ? ["--top-p", nixToString(opts.topP)] : []),
    ...(opts.topK !== undefined ? ["--top-k", nixToString(opts.topK)] : []),
    ...(opts.minP !== undefined ? ["--min-p", nixToString(opts.minP)] : []),
  ]

  const specProfile = opts.specProfile ?? {}
  const specArgs: string[] =
    specProfile.enabled === true
      ? [
          "--spec-type",
          specProfile.specType ?? "draft-mtp",
          ...(specProfile.draftModel !== undefined
            ? ["--model-draft", specProfile.draftModel]
            : []),
          ...(specProfile.draftTokensMax !== undefined
            ? ["--spec-draft-n-max", nixToString(specProfile.draftTokensMax)]
            : []),
          ...(specProfile.draftPMin !== undefined
            ? ["--spec-draft-p-min", nixToString(specProfile.draftPMin)]
            : []),
          ...(specProfile.draftPSplit !== undefined
            ? ["--spec-draft-p-split", nixToString(specProfile.draftPSplit)]
            : []),
          ...(specProfile.draftGpuLayers !== undefined
            ? [
                "--spec-draft-ngl",
                typeof specProfile.draftGpuLayers === "string"
                  ? specProfile.draftGpuLayers
                  : specProfile.draftGpuLayers.value < 0
                    ? "all"
                    : String(specProfile.draftGpuLayers.value),
              ]
            : []),
          ...(specProfile.draftCacheTypeK !== undefined
            ? ["--cache-type-k-draft", specProfile.draftCacheTypeK]
            : []),
          ...(specProfile.draftCacheTypeV !== undefined
            ? ["--cache-type-v-draft", specProfile.draftCacheTypeV]
            : []),
        ]
      : []

  const extraArgs: string[] = opts.extraArgs ?? []

  return [
    llamaServerPath,
    "--port",
    "${PORT}",
    "-hf",
    hfRef,
    "--jinja",
    "--ctx-size",
    ctxSize,
    "--cache-type-k",
    cacheTypeK,
    "--cache-type-v",
    cacheTypeV,
    "--gpu-layers",
    gpuLayers,
    ...reasoningArgs,
    ...templateArgs,
    ...samplingArgs,
    ...specArgs,
    ...extraArgs,
  ].join(" ")
}

export interface SwapConfig {
  globalTTL: number
  healthCheckTimeout: number
  routing: {
    router: {
      use: string
      settings: {
        groups: {
          "local-llms": {
            swap: boolean
            exclusive: boolean
            members: string[]
          }
        }
      }
    }
  }
  models: {
    [name: string]: {
      checkEndpoint: string
      cmd: string
      ttl: number
    }
  }
}

/**
 * The llama-swap `config.yaml`, ported from `swapConfig` in llama-swap.nix.
 * `llamaServerPath` stands in for the flake's `${pkgs.llama-cpp}/bin/llama-server`.
 */
export function generateSwapConfig(
  registry: Registry,
  opts: { llamaServerPath: string },
): SwapConfig {
  const localModels = registry.local
  const models: SwapConfig["models"] = {}
  for (const name of Object.keys(localModels)) {
    const entry = localModels[name]
    const o = entry.options ?? {}
    models[name] = {
      checkEndpoint: "/health",
      cmd: swapCmd(name, entry, opts.llamaServerPath),
      ttl: o.ttl !== undefined && o.ttl.value >= 0 ? o.ttl.value : 120,
    }
  }
  return {
    healthCheckTimeout: 300,
    globalTTL: 0,
    routing: {
      router: {
        use: "group",
        settings: {
          groups: {
            "local-llms": {
              swap: true,
              exclusive: true,
              members: Object.keys(localModels).sort(),
            },
          },
        },
      },
    },
    models,
  }
}

// --- opencode.json ------------------------------------------------------------

function mkOpencodeLimit(entry: ModelEntry): { context: number; output: number } {
  const opts = entry.options ?? {}
  const ctxSize =
    opts.ctxSize !== undefined && opts.ctxSize.value > 0 ? opts.ctxSize.value : 65536
  const outputLimit =
    opts.outputLimit !== undefined && opts.outputLimit.value > 0
      ? opts.outputLimit.value
      : ctxSize >= 65536
        ? 16384
        : 8192
  return { context: ctxSize, output: outputLimit }
}

/**
 * The auxiliary (small) model: the local entry with the smallest context window,
 * alphabetical tiebreak. Ported from `smallModelRef` in opencode.nix.
 */
export function smallModelRef(registry: Registry): string {
  const names = Object.keys(registry.local)
  const ctxOf = (name: string): number => mkOpencodeLimit(registry.local[name]).context
  const sorted = [...names].sort((a, b) => {
    if (ctxOf(a) !== ctxOf(b)) return ctxOf(a) < ctxOf(b) ? -1 : 1
    return a < b ? -1 : a > b ? 1 : 0
  })
  if (sorted.length === 0) return "llama.cpp/qwen3-8b"
  return `llama.cpp/${sorted[0]}`
}

export interface OpencodeConfig {
  $schema: string
  model: string
  small_model: string
  mcp: { [key: string]: Json }
  provider: {
    "llama.cpp": {
      npm: string
      name: string
      options: {
        baseURL: string
        logsDirectory: string
        logFile: string
      }
      models: {
        [name: string]: {
          name: string
          limit: { context: number; output: number }
        }
      }
    }
  }
  plugin: string[]
}

/**
 * The `opencode.json`, ported from `opencodeConfig` in opencode.nix. The MCP and
 * plugin sections are passed through from the registry's `opencode` section
 * (the flake hardcoded them; the runtime registry carries them).
 */
export function generateOpencodeConfig(registry: Registry): OpencodeConfig {
  const localModels = registry.local
  const models: OpencodeConfig["provider"]["llama.cpp"]["models"] = {}
  for (const name of Object.keys(localModels)) {
    const entry = localModels[name]
    models[name] = {
      name: entry.displayName ?? name,
      limit: mkOpencodeLimit(entry),
    }
  }
  const defaultRef = `${registry.default.provider}/${registry.default.name}`
  return {
    $schema: "https://opencode.ai/config.json",
    model: defaultRef,
    small_model: smallModelRef(registry),
    mcp: registry.opencode.mcp ?? {},
    provider: {
      "llama.cpp": {
        npm: "@ai-sdk/openai-compatible",
        name: "llama server (local)",
        options: {
          baseURL: "http://127.0.0.1:8080/v1",
          logsDirectory:
            "${HOME}/.config/nixos-flake/users/spyro/modules/productivity/llm-agent/logs",
          logFile: "opencode-llama-server.log",
        },
        models,
      },
    },
    plugin: registry.opencode.plugin ?? [],
  }
}

// --- unload-policy.json -------------------------------------------------------

export interface UnloadPolicyConfig {
  idleThresholdSeconds: number
  settleSeconds: number
  backend: string
  localProviderId: string
}

/**
 * The `unload-policy.json`, ported from `unloadPolicyConfig` in
 * unload-policy.nix. The thresholds are registry data; the backend URL and
 * local provider id are derived.
 */
export function generateUnloadPolicy(
  registry: Registry,
  opts: { host: string; port: string; localProviderId: string },
): UnloadPolicyConfig {
  return {
    idleThresholdSeconds: registry.unloadPolicy.idleThresholdSeconds.value,
    settleSeconds: registry.unloadPolicy.settleSeconds.value,
    backend: `http://${opts.host}:${opts.port}`,
    localProviderId: opts.localProviderId,
  }
}
