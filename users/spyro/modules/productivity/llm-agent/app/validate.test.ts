import { describe, expect, test } from "bun:test"
import { parseNixJson, type Json } from "./json.js"
import { validateRegistry } from "./registry.js"

// A minimal valid single-file registry, used as the base for the mutation cases.
function baseRegistry(): Record<string, unknown> {
  return {
    version: 1,
    default: { provider: "llama.cpp", name: "m1" },
    unloadPolicy: { idleThresholdSeconds: 300, settleSeconds: 15 },
    local: {
      m1: {
        displayName: "Model One",
        hfRef: "owner/repo:quant",
        options: { ctxSize: 4096, gpuLayers: -1, cacheTypeK: "q4_0", cacheTypeV: "q4_0" },
      },
    },
    cloud: { "big-pickle": "big-pickle" },
    opencode: { mcp: {}, plugin: [] },
  }
}

// Parse a JS object into the Nix-JSON form (numbers become NixNum) so the
// validator sees the same shape the real parser produces. Integers stay ints.
function toNixJsonValue(v: unknown): unknown {
  if (v === null || v === undefined) return null
  if (typeof v === "number") {
    // Mirror Nix fromJSON: an integer literal is an int, a fractional is a float.
    return { __num: v, isFloat: !Number.isInteger(v) }
  }
  if (Array.isArray(v)) return v.map(toNixJsonValue)
  if (typeof v === "object") {
    const out: Record<string, unknown> = {}
    for (const [k, val] of Object.entries(v)) out[k] = toNixJsonValue(val)
    return out
  }
  return v
}

// The validator works on the parsed (NixNum) form. Build it from a JS object by
// round-tripping through the real parser, so the int/float tags are authentic.
function validate(obj: unknown): string[] {
  const text = JSON.stringify(obj)
  const parsed = parseNixJson(text)
  return validateRegistry(parsed as { [key: string]: Json })
}

describe("validateRegistry", () => {
  test("accepts a well-formed registry", () => {
    expect(validate(baseRegistry())).toEqual([])
  })

  test("rejects a missing version", () => {
    const r = baseRegistry()
    delete r.version
    expect(validate(r)).toContain("registry: 'version' is required and must be a number")
  })

  test("rejects a malformed default", () => {
    const r = baseRegistry()
    r.default = { provider: "llama.cpp" }
    expect(validate(r)).toContain(
      "config.json: 'default' must be an object with string 'provider' and 'name'",
    )
  })

  test("rejects an unregistered default model", () => {
    const r = baseRegistry()
    r.default = { provider: "llama.cpp", name: "ghost" }
    expect(validate(r)).toContain("config.json: default model 'llama.cpp/ghost' is not registered")
  })

  test("rejects a non-object local section", () => {
    const r = baseRegistry()
    r.local = []
    expect(validate(r)).toContain("registry: 'local' must be an object")
  })

  test("rejects a non-string cloud value", () => {
    const r = baseRegistry()
    r.cloud = { "big-pickle": 42 }
    expect(validate(r)).toContain("cloud model 'big-pickle': value must be a string")
  })

  test("rejects a missing unloadPolicy field", () => {
    const r = baseRegistry()
    r.unloadPolicy = { idleThresholdSeconds: 300 }
    expect(validate(r)).toContain(
      "config.json: 'unloadPolicy.settleSeconds' is required and must be a positive integer",
    )
  })

  test("rejects a non-positive unloadPolicy threshold", () => {
    const r = baseRegistry()
    r.unloadPolicy = { idleThresholdSeconds: 0, settleSeconds: 15 }
    expect(validate(r)).toContain(
      "config.json: 'unloadPolicy.idleThresholdSeconds' is required and must be a positive integer",
    )
  })

  test("rejects an unknown unloadPolicy field", () => {
    const r = baseRegistry()
    r.unloadPolicy = { idleThresholdSeconds: 300, settleSeconds: 15, extra: 1 }
    expect(validate(r)).toContain("config.json: unknown unloadPolicy field 'extra'")
  })
})

describe("entry validation", () => {
  test("rejects a missing displayName", () => {
    const r = baseRegistry()
    const e = (r.local as Record<string, Record<string, unknown>>).m1
    delete e.displayName
    expect(validate(r)).toContain("model 'm1': 'displayName' is required and must be a string")
  })

  test("rejects a malformed hfRef", () => {
    const r = baseRegistry()
    const e = (r.local as Record<string, Record<string, unknown>>).m1
    e.hfRef = "no-slash-or-colon"
    expect(validate(r)).toContain(
      'model \'m1\': \'hfRef\' is required, must be a string like "owner/repo:quant"',
    )
  })

  test("rejects an unknown top-level entry field", () => {
    const r = baseRegistry()
    const e = (r.local as Record<string, Record<string, unknown>>).m1
    e.bogus = 1
    expect(validate(r)).toContain("model 'm1': unknown field 'bogus'")
  })

  test("rejects a non-string _comment", () => {
    const r = baseRegistry()
    const e = (r.local as Record<string, Record<string, unknown>>).m1
    e._comment = 42
    expect(validate(r)).toContain("model 'm1': '_comment', if present, must be a string")
  })
})

describe("options validation", () => {
  function withOptions(opts: Record<string, unknown>): string[] {
    const r = baseRegistry()
    const e = (r.local as Record<string, Record<string, unknown>>).m1
    e.options = opts
    return validate(r)
  }

  test("rejects a non-object options", () => {
    expect(withOptions([] as unknown as Record<string, unknown>)).toContain(
      "model 'm1': 'options' must be an object",
    )
  })

  test("rejects an unknown options field", () => {
    expect(withOptions({ ctxSize: 4096, bogus: 1 })).toContain(
      "model 'm1': unknown options field 'bogus'",
    )
  })

  test("rejects a non-positive ctxSize", () => {
    expect(withOptions({ ctxSize: 0 })).toContain(
      "model 'm1': 'options.ctxSize' must be a positive integer",
    )
  })

  test("rejects a float ctxSize (must be an int)", () => {
    expect(withOptions({ ctxSize: 4096.5 })).toContain(
      "model 'm1': 'options.ctxSize' must be a positive integer",
    )
  })

  test("rejects a bad cacheType", () => {
    expect(withOptions({ cacheType: "q9_9" })).toContain(
      "model 'm1': 'options.cacheType' must be one of f32 f16 bf16 q8_0 q4_0 q4_1 iq4_nl q5_0 q5_1",
    )
  })

  test("rejects cacheType combined with explicit cacheTypeK/V", () => {
    expect(withOptions({ cacheType: "q4_0", cacheTypeK: "q4_0" })).toContain(
      "model 'm1': 'options.cacheType' shorthand cannot be combined with explicit 'cacheTypeK'/'cacheTypeV'",
    )
  })

  test("rejects a negative ttl", () => {
    expect(withOptions({ ttl: -1 })).toContain(
      "model 'm1': 'options.ttl' must be a non-negative integer (0 = never evict)",
    )
  })

  test("rejects a negative temperature", () => {
    expect(withOptions({ temperature: -0.1 })).toContain(
      "model 'm1': 'options.temperature' must be a number >= 0",
    )
  })

  test("rejects a topP above 1", () => {
    expect(withOptions({ topP: 1.5 })).toContain(
      "model 'm1': 'options.topP' must be a number in [0, 1]",
    )
  })

  test("rejects a non-integer topK", () => {
    expect(withOptions({ topK: 20.5 })).toContain(
      "model 'm1': 'options.topK' must be an integer >= 0 (0 = disabled)",
    )
  })

  test("rejects a non-list extraArgs", () => {
    expect(withOptions({ extraArgs: "not-a-list" })).toContain(
      "model 'm1': 'options.extraArgs' must be a list of strings",
    )
  })

  test("accepts a null reasoningBudget (server default)", () => {
    expect(withOptions({ reasoningBudget: null })).toEqual([])
  })

  test("rejects a negative reasoningBudget", () => {
    expect(withOptions({ reasoningBudget: -2 })).toContain(
      "model 'm1': 'options.reasoningBudget' must be an integer >= -1 (-1 = unrestricted) or null (server default)",
    )
  })
})

describe("specProfile validation", () => {
  function withSpecProfile(profile: Record<string, unknown>): string[] {
    const r = baseRegistry()
    const e = (r.local as Record<string, Record<string, unknown>>).m1
    e.options = { ctxSize: 4096, specProfile: profile }
    return validate(r)
  }

  test("rejects a non-object specProfile", () => {
    expect(withSpecProfile([] as unknown as Record<string, unknown>)).toContain(
      "model 'm1': 'options.specProfile' must be an object",
    )
  })

  test("rejects an unknown specProfile field", () => {
    expect(withSpecProfile({ enabled: true, bogus: 1 })).toContain(
      "model 'm1': unknown specProfile field 'bogus'",
    )
  })

  test("rejects a non-boolean enabled", () => {
    expect(withSpecProfile({ enabled: "yes" })).toContain(
      "model 'm1': 'options.specProfile.enabled' must be a boolean",
    )
  })

  test("rejects an invalid specType", () => {
    expect(withSpecProfile({ enabled: true, specType: "nope" })).toContain(
      "model 'm1': 'options.specProfile.specType' must be one of none draft-simple draft-eagle3 draft-mtp draft-dflash draft-dspark ngram-simple ngram-map-k ngram-map-k4v ngram-mod ngram-cache",
    )
  })

  test("rejects a non-positive draftTokensMax", () => {
    expect(withSpecProfile({ enabled: true, draftTokensMax: 0 })).toContain(
      "model 'm1': 'options.specProfile.draftTokensMax' must be a positive integer",
    )
  })

  test("rejects a draftPMin above 1", () => {
    expect(withSpecProfile({ enabled: true, draftPMin: 2 })).toContain(
      "model 'm1': 'options.specProfile.draftPMin' must be a number in [0, 1]",
    )
  })

  test("accepts draftGpuLayers as 'auto'", () => {
    expect(withSpecProfile({ enabled: true, draftGpuLayers: "auto" })).toEqual([])
  })

  test("rejects a bad draftCacheTypeK", () => {
    expect(withSpecProfile({ enabled: true, draftCacheTypeK: "q9_9" })).toContain(
      "model 'm1': 'options.specProfile.draftCacheTypeK' must be a KV cache type",
    )
  })
})
