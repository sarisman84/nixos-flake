import { describe, expect, test } from "bun:test"
import { readFileSync } from "node:fs"
import { parseNixJson, type Json } from "./json.js"
import { toRegistry, validateRegistry } from "./registry.js"
import {
  generateOpencodeConfig,
  generateSwapConfig,
  generateUnloadPolicy,
  smallModelRef,
  toNixJson,
} from "./generate.js"

const FIXTURE = readFileSync(new URL("./fixtures/registry.json", import.meta.url), "utf8")
// Stands in for the flake's `${pkgs.llama-cpp}/bin/llama-server`; fixed so the
// snapshot is stable across nix flake updates (the path is an input, not part
// of the generation logic the snapshot pins).
const LLAMA_SERVER = "/nix/store/llama-cpp/bin/llama-server"
const HOST = "127.0.0.1"
const PORT = "8080"
const LOCAL_PROVIDER = "llama.cpp"

function loadRegistry() {
  const reg = parseNixJson(FIXTURE) as { [key: string]: Json }
  const errors = validateRegistry(reg)
  expect(errors).toEqual([])
  return toRegistry(reg)
}

describe("generateSwapConfig (config.yaml)", () => {
  test("pins the flake's config.yaml", () => {
    const reg = loadRegistry()
    const out = toNixJson(generateSwapConfig(reg, { llamaServerPath: LLAMA_SERVER }))
    expect(out).toMatchSnapshot()
  })

  test("sets the one-resident group and global TTL", () => {
    const reg = loadRegistry()
    const cfg = generateSwapConfig(reg, { llamaServerPath: LLAMA_SERVER })
    expect(cfg.globalTTL).toBe(0)
    expect(cfg.healthCheckTimeout).toBe(300)
    const group = cfg.routing.router.settings.groups["local-llms"]
    expect(group.swap).toBe(true)
    expect(group.exclusive).toBe(true)
    expect(group.members).toEqual(Object.keys(reg.local).sort())
    expect(Object.keys(cfg.models).sort()).toEqual(Object.keys(reg.local).sort())
  })

  test("renders float sampling params with six decimals (the Nix toString case)", () => {
    const reg = loadRegistry()
    const cfg = generateSwapConfig(reg, { llamaServerPath: LLAMA_SERVER })
    // gpt-oss-20b has temperature 1.0, topP 1.0, minP 0.0 (floats) and topK 64 (int).
    const cmd = cfg.models["gpt-oss-20b"].cmd
    expect(cmd).toContain("--temperature 1.000000")
    expect(cmd).toContain("--top-p 1.000000")
    expect(cmd).toContain("--top-k 64")
    expect(cmd).toContain("--min-p 0.000000")
  })

  test("emits the spec-type flag for an enabled specProfile", () => {
    const reg = loadRegistry()
    const cfg = generateSwapConfig(reg, { llamaServerPath: LLAMA_SERVER })
    expect(cfg.models["qwen3-30b-a3b-ngram"].cmd).toContain("--spec-type ngram-mod")
    // A disabled specProfile emits no spec flags.
    expect(cfg.models["qwen3-30b-a3b"].cmd).not.toContain("--spec-type")
  })
})

describe("generateOpencodeConfig (opencode.json)", () => {
  test("pins the flake's opencode.json", () => {
    const reg = loadRegistry()
    const out = toNixJson(generateOpencodeConfig(reg))
    expect(out).toMatchSnapshot()
  })

  test("derives model and small_model", () => {
    const reg = loadRegistry()
    const cfg = generateOpencodeConfig(reg)
    expect(cfg.model).toBe("llama.cpp/qwen3-30b-a3b")
    // devstral-small-2-24b is the smallest-context local model (131072, alphabetical
    // tiebreak among the 131072 entries).
    expect(cfg.small_model).toBe("llama.cpp/devstral-small-2-24b")
    expect(smallModelRef(reg)).toBe("llama.cpp/devstral-small-2-24b")
  })

  test("emits every local model with its display name and limits", () => {
    const reg = loadRegistry()
    const cfg = generateOpencodeConfig(reg)
    const models = cfg.provider["llama.cpp"].models
    expect(Object.keys(models).sort()).toEqual(Object.keys(reg.local).sort())
    expect(models["qwen3.8-27b-200k"].name).toBe("Qwen3.8 27B reasoning (200k opt-in)")
    expect(models["qwen3.8-27b-200k"].limit).toEqual({ context: 200000, output: 16384 })
    expect(models["qwen3-30b-a3b"].limit).toEqual({ context: 131072, output: 16384 })
  })

  test("passes through the registry's mcp and plugin sections", () => {
    const reg = loadRegistry()
    const cfg = generateOpencodeConfig(reg)
    expect(Object.keys(cfg.mcp).sort()).toEqual(["figma", "stitch", "supabase"])
    expect(cfg.plugin).toEqual(["opencode-parser"])
  })
})

describe("generateUnloadPolicy (unload-policy.json)", () => {
  test("pins the flake's unload-policy.json", () => {
    const reg = loadRegistry()
    const out = toNixJson(
      generateUnloadPolicy(reg, { host: HOST, port: PORT, localProviderId: LOCAL_PROVIDER }),
    )
    expect(out).toMatchSnapshot()
  })

  test("carries the thresholds, loopback backend, and local provider id", () => {
    const reg = loadRegistry()
    const cfg = generateUnloadPolicy(reg, { host: HOST, port: PORT, localProviderId: LOCAL_PROVIDER })
    expect(cfg).toEqual({
      idleThresholdSeconds: 300,
      settleSeconds: 15,
      backend: "http://127.0.0.1:8080",
      localProviderId: "llama.cpp",
    })
  })
})
