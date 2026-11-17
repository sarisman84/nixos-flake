/**
 * The registry: the single source of truth for model configuration, and the
 * validation rules ported from `registry.nix`.
 *
 * The runtime app reads a single-file registry (map #89): `{ version, default,
 * unloadPolicy, local, cloud, opencode }`. This module validates that shape and
 * reports the same readable errors the flake's assertions did, so a malformed
 * registry fails loudly with a message a human can act on.
 *
 * Numbers arrive as `NixNum` (from `json.ts`) so the int/float distinction the
 * generators depend on is preserved.
 */
import {
  type Json,
  isBool,
  isFloat,
  isInt,
  isNum,
  isObject,
  isString,
  NixNum,
} from "./json.js"

/** A `llama-server` sampling / runtime option for one model. */
export interface ModelOptions {
  ctxSize?: NixNum
  outputLimit?: NixNum
  gpuLayers?: NixNum
  cacheType?: string
  cacheTypeK?: string
  cacheTypeV?: string
  reasoningBudget?: NixNum | null
  ttl?: NixNum
  temperature?: NixNum
  topP?: NixNum
  topK?: NixNum
  minP?: NixNum
  specProfile?: SpecProfile
  extraArgs?: string[]
  templateOverride?: string
}

/** Speculative-decoding profile (llama.cpp `--spec-type` and friends). */
export interface SpecProfile {
  enabled?: boolean
  specType?: string
  draftModel?: string
  draftTokensMax?: NixNum
  draftPMin?: NixNum
  draftPSplit?: NixNum
  draftGpuLayers?: NixNum | "auto" | "all"
  draftCacheTypeK?: string
  draftCacheTypeV?: string
}

/** One local model entry. */
export interface ModelEntry {
  displayName: string
  hfRef: string
  options?: ModelOptions
  _comment?: string
}

/** The registry's `default` model reference. */
export interface DefaultRef {
  provider: string
  name: string
}

/** The unload-policy thresholds (registry data, not code constants). */
export interface UnloadPolicy {
  idleThresholdSeconds: NixNum
  settleSeconds: NixNum
}

/** The `opencode` passthrough section (MCP servers + plugin list). */
export interface OpencodeSection {
  mcp?: { [key: string]: Json }
  plugin?: string[]
}

/** The single-file runtime registry. */
export interface Registry {
  version: NixNum
  default: DefaultRef
  unloadPolicy: UnloadPolicy
  local: { [key: string]: ModelEntry }
  cloud: { [key: string]: string }
  opencode: OpencodeSection
}

// The allowed-value lists, ported verbatim from registry.nix.
export const VALID_CACHE_TYPES = [
  "f32",
  "f16",
  "bf16",
  "q8_0",
  "q4_0",
  "q4_1",
  "iq4_nl",
  "q5_0",
  "q5_1",
]
export const VALID_OPTION_FIELDS = [
  "ctxSize",
  "outputLimit",
  "gpuLayers",
  "cacheType",
  "cacheTypeK",
  "cacheTypeV",
  "reasoningBudget",
  "ttl",
  "temperature",
  "topP",
  "topK",
  "minP",
  "specProfile",
  "extraArgs",
  "templateOverride",
]
export const VALID_SPEC_FIELDS = [
  "enabled",
  "specType",
  "draftModel",
  "draftTokensMax",
  "draftPMin",
  "draftPSplit",
  "draftGpuLayers",
  "draftCacheTypeK",
  "draftCacheTypeV",
]
// llama.cpp --spec-type list as of v0.5.0 (nixos-unstable). Re-verify on
// `nix flake update`.
export const VALID_SPEC_TYPES = [
  "none",
  "draft-simple",
  "draft-eagle3",
  "draft-mtp",
  "draft-dflash",
  "draft-dspark",
  "ngram-simple",
  "ngram-map-k",
  "ngram-map-k4v",
  "ngram-mod",
  "ngram-cache",
]
const VALID_ENTRY_FIELDS = ["displayName", "hfRef", "options", "_comment"]

/** Nix `toString` on a list of strings: space-separated, no brackets. */
function listToString(list: string[]): string {
  return list.join(" ")
}

/**
 * Nix `errIf`: report `msg` when `cond` is FALSE. The *expected* shape goes in
 * whole, so a missing field reads as an error, not a silent pass.
 */
function errIf(cond: boolean, msg: string): string[] {
  return cond ? [] : [msg]
}

/** Nix `attrNames`, sorted (Nix sorts attrset names). */
function attrNames(obj: { [key: string]: Json }): string[] {
  return Object.keys(obj).sort()
}

function checkSpecProfile(name: string, profile: Json): string[] {
  if (!isObject(profile)) {
    return [`model '${name}': 'options.specProfile' must be an object`]
  }
  const unknown = attrNames(profile).filter((f) => !VALID_SPEC_FIELDS.includes(f))
  return [
    ...unknown.map((f) => `model '${name}': unknown specProfile field '${f}'`),
    ...errIf(
      !("enabled" in profile) || isBool(profile.enabled),
      `model '${name}': 'options.specProfile.enabled' must be a boolean`,
    ),
    ...errIf(
      !("specType" in profile) ||
        (isString(profile.specType) && VALID_SPEC_TYPES.includes(profile.specType)),
      `model '${name}': 'options.specProfile.specType' must be one of ${listToString(VALID_SPEC_TYPES)}`,
    ),
    ...errIf(
      !("draftModel" in profile) || isString(profile.draftModel),
      `model '${name}': 'options.specProfile.draftModel' must be a string`,
    ),
    ...errIf(
      !("draftTokensMax" in profile) || (isInt(profile.draftTokensMax) && profile.draftTokensMax.value > 0),
      `model '${name}': 'options.specProfile.draftTokensMax' must be a positive integer`,
    ),
    ...errIf(
      !("draftPMin" in profile) ||
        ((isFloat(profile.draftPMin) || isInt(profile.draftPMin)) &&
          profile.draftPMin.value >= 0 &&
          profile.draftPMin.value <= 1),
      `model '${name}': 'options.specProfile.draftPMin' must be a number in [0, 1]`,
    ),
    ...errIf(
      !("draftPSplit" in profile) ||
        ((isFloat(profile.draftPSplit) || isInt(profile.draftPSplit)) &&
          profile.draftPSplit.value >= 0 &&
          profile.draftPSplit.value <= 1),
      `model '${name}': 'options.specProfile.draftPSplit' must be a number in [0, 1]`,
    ),
    ...errIf(
      !("draftGpuLayers" in profile) ||
        ((isInt(profile.draftGpuLayers) && profile.draftGpuLayers.value >= -1) ||
          (isString(profile.draftGpuLayers) &&
            (profile.draftGpuLayers === "auto" || profile.draftGpuLayers === "all"))),
      `model '${name}': 'options.specProfile.draftGpuLayers' must be an integer >= -1 or 'auto'/'all'`,
    ),
    ...errIf(
      !("draftCacheTypeK" in profile) ||
        (isString(profile.draftCacheTypeK) && VALID_CACHE_TYPES.includes(profile.draftCacheTypeK)),
      `model '${name}': 'options.specProfile.draftCacheTypeK' must be a KV cache type`,
    ),
    ...errIf(
      !("draftCacheTypeV" in profile) ||
        (isString(profile.draftCacheTypeV) && VALID_CACHE_TYPES.includes(profile.draftCacheTypeV)),
      `model '${name}': 'options.specProfile.draftCacheTypeV' must be a KV cache type`,
    ),
  ]
}

function checkOptions(name: string, opts: Json): string[] {
  if (!isObject(opts)) {
    return [`model '${name}': 'options' must be an object`]
  }
  const unknown = attrNames(opts).filter((f) => !VALID_OPTION_FIELDS.includes(f))
  const cacheList = listToString(VALID_CACHE_TYPES)
  return [
    ...unknown.map((f) => `model '${name}': unknown options field '${f}'`),
    ...errIf(
      !("ctxSize" in opts) || (isInt(opts.ctxSize) && opts.ctxSize.value > 0),
      `model '${name}': 'options.ctxSize' must be a positive integer`,
    ),
    ...errIf(
      !("outputLimit" in opts) || (isInt(opts.outputLimit) && opts.outputLimit.value > 0),
      `model '${name}': 'options.outputLimit' must be a positive integer`,
    ),
    ...errIf(
      !("gpuLayers" in opts) || isInt(opts.gpuLayers),
      `model '${name}': 'options.gpuLayers' must be an integer (-1 = full offload)`,
    ),
    ...errIf(
      !("cacheType" in opts) || (isString(opts.cacheType) && VALID_CACHE_TYPES.includes(opts.cacheType)),
      `model '${name}': 'options.cacheType' must be one of ${cacheList}`,
    ),
    ...errIf(
      !("cacheTypeK" in opts) || (isString(opts.cacheTypeK) && VALID_CACHE_TYPES.includes(opts.cacheTypeK)),
      `model '${name}': 'options.cacheTypeK' must be one of ${cacheList}`,
    ),
    ...errIf(
      !("cacheTypeV" in opts) || (isString(opts.cacheTypeV) && VALID_CACHE_TYPES.includes(opts.cacheTypeV)),
      `model '${name}': 'options.cacheTypeV' must be one of ${cacheList}`,
    ),
    ...errIf(
      !("cacheType" in opts) || (!("cacheTypeK" in opts) && !("cacheTypeV" in opts)),
      `model '${name}': 'options.cacheType' shorthand cannot be combined with explicit 'cacheTypeK'/'cacheTypeV'`,
    ),
    ...errIf(
      !("reasoningBudget" in opts) ||
        (opts.reasoningBudget === null ||
          (isInt(opts.reasoningBudget) && opts.reasoningBudget.value >= -1)),
      `model '${name}': 'options.reasoningBudget' must be an integer >= -1 (-1 = unrestricted) or null (server default)`,
    ),
    ...errIf(
      !("ttl" in opts) || (isInt(opts.ttl) && opts.ttl.value >= 0),
      `model '${name}': 'options.ttl' must be a non-negative integer (0 = never evict)`,
    ),
    ...errIf(
      !("temperature" in opts) ||
        ((isFloat(opts.temperature) || isInt(opts.temperature)) && opts.temperature.value >= 0),
      `model '${name}': 'options.temperature' must be a number >= 0`,
    ),
    ...errIf(
      !("topP" in opts) ||
        ((isFloat(opts.topP) || isInt(opts.topP)) &&
          opts.topP.value >= 0 &&
          opts.topP.value <= 1),
      `model '${name}': 'options.topP' must be a number in [0, 1]`,
    ),
    ...errIf(
      !("topK" in opts) || (isInt(opts.topK) && opts.topK.value >= 0),
      `model '${name}': 'options.topK' must be an integer >= 0 (0 = disabled)`,
    ),
    ...errIf(
      !("minP" in opts) ||
        ((isFloat(opts.minP) || isInt(opts.minP)) &&
          opts.minP.value >= 0 &&
          opts.minP.value <= 1),
      `model '${name}': 'options.minP' must be a number in [0, 1]`,
    ),
    ...("specProfile" in opts ? checkSpecProfile(name, opts.specProfile) : []),
    ...errIf(
      !("extraArgs" in opts) ||
        (Array.isArray(opts.extraArgs) && opts.extraArgs.every((a) => isString(a))),
      `model '${name}': 'options.extraArgs' must be a list of strings`,
    ),
    ...errIf(
      !("templateOverride" in opts) || isString(opts.templateOverride),
      `model '${name}': 'options.templateOverride' must be a string`,
    ),
  ]
}

function checkEntry(name: string, entry: Json): string[] {
  if (!isObject(entry)) {
    return [`model '${name}': entry must be an object`]
  }
  const unknown = attrNames(entry).filter((f) => !VALID_ENTRY_FIELDS.includes(f))
  return [
    ...errIf(
      !("_comment" in entry) || isString(entry._comment),
      `model '${name}': '_comment', if present, must be a string`,
    ),
    ...unknown.map((f) => `model '${name}': unknown field '${f}'`),
    ...errIf(
      "displayName" in entry && isString(entry.displayName),
      `model '${name}': 'displayName' is required and must be a string`,
    ),
    ...errIf(
      "hfRef" in entry && isString(entry.hfRef) && /.+\/.+:.+/ .test(entry.hfRef),
      `model '${name}': 'hfRef' is required, must be a string like "owner/repo:quant"`,
    ),
    ...("options" in entry ? checkOptions(name, entry.options) : []),
  ]
}

function checkDefault(reg: { [key: string]: Json }): string[] {
  const d = reg.default
  const ok =
    isObject(d) && "provider" in d && isString(d.provider) && "name" in d && isString(d.name)
  return errIf(
    ok,
    "config.json: 'default' must be an object with string 'provider' and 'name'",
  )
}

function checkUnloadPolicy(reg: { [key: string]: Json }): string[] {
  const policy = reg.unloadPolicy
  if (!isObject(policy)) {
    return ["config.json: 'unloadPolicy' must be an object"]
  }
  const positiveInt = (v: Json): boolean => isInt(v) && v.value > 0
  return [
    ...errIf(
      "idleThresholdSeconds" in policy && positiveInt(policy.idleThresholdSeconds),
      "config.json: 'unloadPolicy.idleThresholdSeconds' is required and must be a positive integer",
    ),
    ...errIf(
      "settleSeconds" in policy && positiveInt(policy.settleSeconds),
      "config.json: 'unloadPolicy.settleSeconds' is required and must be a positive integer",
    ),
    ...attrNames(policy)
      .filter((f) => f !== "idleThresholdSeconds" && f !== "settleSeconds")
      .map((f) => `config.json: unknown unloadPolicy field '${f}'`),
  ]
}

/**
 * Validate the assembled single-file registry. Returns the list of readable
 * errors (empty when valid). Mirrors `registry.nix`'s `registryErrors` over the
 * single-file shape: `default`, the `local` entries, the `cloud` map, the
 * default-reference check, and `unloadPolicy`.
 */
export function validateRegistry(reg: { [key: string]: Json }): string[] {
  if (!isObject(reg)) {
    return ["registry: top level must be an object"]
  }
  const errors: string[] = []

  // version is required by the single-file shape (map #89).
  errors.push(
    ...errIf(
      "version" in reg && isNum(reg.version),
      "registry: 'version' is required and must be a number",
    ),
  )

  errors.push(...checkDefault(reg))

  const local = reg.local
  if (!isObject(local)) {
    errors.push("registry: 'local' must be an object")
  } else {
    for (const name of attrNames(local)) {
      errors.push(...checkEntry(name, local[name]))
    }
  }

  const cloud = reg.cloud
  if (!isObject(cloud)) {
    errors.push("cloud-models.json: must be an object of model key -> value")
  } else {
    for (const n of attrNames(cloud)) {
      errors.push(...errIf(isString(cloud[n]), `cloud model '${n}': value must be a string`))
    }
  }

  // The default reference must point at a registered model.
  const d = reg.default
  if (
    isObject(d) &&
    "provider" in d &&
    isString(d.provider) &&
    "name" in d &&
    isString(d.name)
  ) {
    const p = d.provider
    const n = d.name
    // The single-file shape keys sections by `local`/`cloud`, not by provider
    // name; map the default's provider to its section.
    const section = p === "llama.cpp" ? reg.local : p === "opencode" ? reg.cloud : reg[p]
    const registered = isObject(section) && n in section
    errors.push(
      ...errIf(registered, `config.json: default model '${p}/${n}' is not registered`),
    )
  }

  errors.push(...checkUnloadPolicy(reg))

  return errors
}

/**
 * Coerce a validated registry into the typed `Registry`. Only call after
 * `validateRegistry` returns no errors; this does not re-check.
 */
export function toRegistry(reg: { [key: string]: Json }): Registry {
  const local: { [key: string]: ModelEntry } = {}
  const localRaw = isObject(reg.local) ? reg.local : {}
  for (const key of Object.keys(localRaw)) {
    const entry = isObject(localRaw[key]) ? localRaw[key] : {}
    local[key] = {
      displayName: isString(entry.displayName) ? entry.displayName : key,
      hfRef: isString(entry.hfRef) ? entry.hfRef : key,
      ...(isObject(entry.options) ? { options: entry.options as ModelOptions } : {}),
      ...(isString(entry._comment) ? { _comment: entry._comment } : {}),
    }
  }
  const cloud: { [key: string]: string } = {}
  const cloudRaw = isObject(reg.cloud) ? reg.cloud : {}
  for (const key of Object.keys(cloudRaw)) {
    cloud[key] = isString(cloudRaw[key]) ? cloudRaw[key] : key
  }
  const d = isObject(reg.default) ? reg.default : {}
  const policyRaw = isObject(reg.unloadPolicy) ? reg.unloadPolicy : {}
  const opencodeRaw = isObject(reg.opencode) ? reg.opencode : {}
  const mcp = isObject(opencodeRaw.mcp) ? opencodeRaw.mcp : undefined
  const plugin = Array.isArray(opencodeRaw.plugin)
    ? (opencodeRaw.plugin as string[])
    : undefined
  return {
    version: isNum(reg.version) ? reg.version : new NixNum(1, false),
    default: {
      provider: isString(d.provider) ? d.provider : "llama.cpp",
      name: isString(d.name) ? d.name : "qwen3-8b",
    },
    unloadPolicy: {
      idleThresholdSeconds: isNum(policyRaw.idleThresholdSeconds)
        ? policyRaw.idleThresholdSeconds
        : new NixNum(0, false),
      settleSeconds: isNum(policyRaw.settleSeconds)
        ? policyRaw.settleSeconds
        : new NixNum(0, false),
    },
    local,
    cloud,
    opencode: {
      ...(mcp !== undefined ? { mcp } : {}),
      ...(plugin !== undefined ? { plugin } : {}),
    },
  }
}
