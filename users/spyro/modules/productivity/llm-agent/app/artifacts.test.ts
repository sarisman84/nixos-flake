import { describe, expect, test } from "bun:test"
import { readFileSync } from "node:fs"
import { parseNixJson, type Json } from "./json.js"
import { toRegistry, validateRegistry } from "./registry.js"
import { buildArtifacts } from "./artifacts.js"

const FIXTURE = readFileSync(new URL("./fixtures/registry.json", import.meta.url), "utf8")
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

const OPTS = { llamaServerPath: LLAMA_SERVER, host: HOST, port: PORT, localProviderId: LOCAL_PROVIDER }

describe("buildArtifacts", () => {
  test("pins the three generated artefacts", () => {
    const reg = loadRegistry()
    const a = buildArtifacts(reg, OPTS)
    expect(a.configYaml).toMatchSnapshot()
    expect(a.opencodeJson).toMatchSnapshot()
    expect(a.unloadPolicyJson).toMatchSnapshot()
  })

  test("config.yaml carries every local model in the one-resident group", () => {
    const reg = loadRegistry()
    const a = buildArtifacts(reg, OPTS)
    // Every local model key appears as a model entry.
    for (const name of Object.keys(reg.local)) {
      expect(a.configYaml).toContain(`"${name}"`)
    }
    // The group is swap + exclusive.
    expect(a.configYaml).toContain('"swap":true')
    expect(a.configYaml).toContain('"exclusive":true')
  })

  test("opencode.json carries the default model, small model, and provider", () => {
    const reg = loadRegistry()
    const a = buildArtifacts(reg, OPTS)
    expect(a.opencodeJson).toContain(`"model":"${reg.default.provider}/${reg.default.name}"`)
    expect(a.opencodeJson).toContain('"small_model":"llama.cpp/devstral-small-2-24b"')
    expect(a.opencodeJson).toContain('"llama.cpp"')
    expect(a.opencodeJson).toContain('"baseURL":"http://127.0.0.1:8080/v1"')
  })

  test("unload-policy.json carries the thresholds and the loopback backend", () => {
    const reg = loadRegistry()
    const a = buildArtifacts(reg, OPTS)
    expect(a.unloadPolicyJson).toContain('"idleThresholdSeconds":300')
    expect(a.unloadPolicyJson).toContain('"settleSeconds":15')
    expect(a.unloadPolicyJson).toContain('"backend":"http://127.0.0.1:8080"')
    expect(a.unloadPolicyJson).toContain('"localProviderId":"llama.cpp"')
  })
})
