import { describe, expect, test } from "bun:test"
import { readFileSync } from "node:fs"
import { parseNixJson, type Json } from "./json.js"
import { toRegistry, validateRegistry } from "./registry.js"
import { applyRegistry, saveRegistry, type ApplyDeps } from "./apply.js"
import { type Paths } from "./paths.js"

const FIXTURE = readFileSync(new URL("./fixtures/registry.json", import.meta.url), "utf8")

const PATHS: Paths = {
  registry: "/home/u/.config/llm-agent/registry.json",
  configYaml: "/home/u/.config/llama-swap/config.yaml",
  unloadPolicy: "/home/u/.config/llama-swap/unload-policy.json",
  opencodeJson: "/home/u/.config/opencode/opencode.json",
  opencodeJsonc: "/home/u/.config/opencode/opencode.jsonc",
  heartbeat: "/home/u/.local/state/llm-agent/heartbeat.json",
  leaseDir: "/home/u/.local/state/llm-agent/leases",
  backendBase: "http://127.0.0.1:8080",
}

const OPTS = {
  llamaServerPath: "/nix/store/llama-cpp/bin/llama-server",
  host: "127.0.0.1",
  port: "8080",
  localProviderId: "llama.cpp",
}

function loadParsed(): { [key: string]: Json } {
  const reg = parseNixJson(FIXTURE) as { [key: string]: Json }
  expect(validateRegistry(reg)).toEqual([])
  return reg
}

function makeDeps(overrides?: Partial<ApplyDeps>): {
  deps: ApplyDeps
  writes: Array<{ path: string; content: string }>
  state: { signals: number }
} {
  const writes: Array<{ path: string; content: string }> = []
  const state = { signals: 0 }
  const deps: ApplyDeps = {
    paths: PATHS,
    opts: OPTS,
    opencodeJsonc: null,
    writeFile: (path, content) => {
      writes.push({ path, content })
    },
    signal: () => {
      state.signals++
      return true
    },
    ...overrides,
  }
  return { deps, writes, state }
}

describe("saveRegistry", () => {
  test("writes only the registry file, does not signal", () => {
    const { deps, writes, state } = makeDeps()
    const result = saveRegistry(loadParsed(), deps)
    expect(result.ok).toBe(true)
    expect(writes).toHaveLength(1)
    expect(writes[0].path).toBe(PATHS.registry)
    expect(state.signals).toBe(0)
  })

  test("refuses to save an invalid registry", () => {
    const reg = loadParsed()
    delete reg.version
    const { deps, writes, state } = makeDeps()
    const result = saveRegistry(reg, deps)
    expect(result.ok).toBe(false)
    expect(result.errors.length).toBeGreaterThan(0)
    expect(writes).toHaveLength(0)
    expect(state.signals).toBe(0)
  })
})

describe("applyRegistry", () => {
  test("validates, writes all four generated files, and signals a reload", () => {
    const { deps, writes, state } = makeDeps({
      opencodeJsonc: '{"plugins":["opencode-skill-creator"]}',
    })
    const result = applyRegistry(loadParsed(), deps)
    expect(result.ok).toBe(true)
    expect(result.errors).toEqual([])
    expect(result.reloaded).toBe(true)
    expect(result.message).toBe("applied — running instances pick it up within a second")
    // registry + config.yaml + opencode.json + unload-policy.json + opencode.jsonc
    expect(writes.map((w) => w.path).sort()).toEqual(
      [
        PATHS.registry,
        PATHS.configYaml,
        PATHS.opencodeJson,
        PATHS.unloadPolicy,
        PATHS.opencodeJsonc,
      ].sort(),
    )
    expect(state.signals).toBe(1)
    // The generated opencode.json is the registry-derived document.
    const oc = writes.find((w) => w.path === PATHS.opencodeJson)
    expect(oc?.content).toContain('"model":"llama.cpp/qwen3-30b-a3b"')
    // The opencode.jsonc is written verbatim (user-owned, not generated).
    const jsonc = writes.find((w) => w.path === PATHS.opencodeJsonc)
    expect(jsonc?.content).toBe('{"plugins":["opencode-skill-creator"]}')
  })

  test("does not write opencode.jsonc when it is null", () => {
    const { deps, writes } = makeDeps({ opencodeJsonc: null })
    applyRegistry(loadParsed(), deps)
    expect(writes.some((w) => w.path === PATHS.opencodeJsonc)).toBe(false)
  })

  test("refuses to apply an invalid registry: no writes, no signal", () => {
    const reg = loadParsed()
    ;(reg.default as { [k: string]: Json }).name = "ghost"
    const { deps, writes, state } = makeDeps()
    const result = applyRegistry(reg, deps)
    expect(result.ok).toBe(false)
    expect(result.errors).toContain("config.json: default model 'llama.cpp/ghost' is not registered")
    expect(writes).toHaveLength(0)
    expect(state.signals).toBe(0)
  })

  test("reports the reload failure but still reports the files written", () => {
    const { deps, writes, state } = makeDeps()
    // A signal that is sent but fails (e.g. the unit is not running).
    deps.signal = () => {
      state.signals++
      return false
    }
    const result = applyRegistry(loadParsed(), deps)
    expect(result.ok).toBe(true)
    expect(result.reloaded).toBe(false)
    expect(writes.length).toBeGreaterThan(0)
    expect(state.signals).toBe(1)
  })

  test("the written registry round-trips through the validator", () => {
    const { deps, writes } = makeDeps()
    applyRegistry(loadParsed(), deps)
    const regWrite = writes.find((w) => w.path === PATHS.registry)
    expect(regWrite).toBeDefined()
    const reparsed = parseNixJson(regWrite!.content) as { [key: string]: Json }
    expect(validateRegistry(reparsed)).toEqual([])
    // The regenerated opencode config matches the generator's output.
    expect(deps.opts).toEqual(OPTS)
  })
})
