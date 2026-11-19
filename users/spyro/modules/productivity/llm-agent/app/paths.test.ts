import { describe, expect, test } from "bun:test"
import { resolvePaths } from "./paths.js"

describe("resolvePaths", () => {
  test("resolves the config files under ~/.config (home-manager layout)", () => {
    const p = resolvePaths({ home: "/home/u" })
    expect(p.registry).toBe("/home/u/.config/llm-agent/registry.json")
    expect(p.configYaml).toBe("/home/u/.config/llama-swap/config.yaml")
    expect(p.unloadPolicy).toBe("/home/u/.config/llama-swap/unload-policy.json")
    expect(p.opencodeJson).toBe("/home/u/.config/opencode/opencode.json")
    expect(p.opencodeJsonc).toBe("/home/u/.config/opencode/opencode.jsonc")
  })

  test("resolves state under ~/.local/state by default", () => {
    const p = resolvePaths({ home: "/home/u" })
    expect(p.heartbeat).toBe("/home/u/.local/state/llm-agent/heartbeat.json")
    expect(p.leaseDir).toBe("/home/u/.local/state/llm-agent/leases")
  })

  test("honours XDG_STATE_HOME for the state files", () => {
    const p = resolvePaths({ home: "/home/u", xdgStateHome: "/state" })
    expect(p.heartbeat).toBe("/state/llm-agent/heartbeat.json")
    expect(p.leaseDir).toBe("/state/llm-agent/leases")
  })

  test("defaults the backend to loopback 127.0.0.1:8080", () => {
    const p = resolvePaths({ home: "/home/u" })
    expect(p.backendBase).toBe("http://127.0.0.1:8080")
  })

  test("honours an explicit backend host and port", () => {
    const p = resolvePaths({ home: "/home/u", backendHost: "localhost", backendPort: "9999" })
    expect(p.backendBase).toBe("http://localhost:9999")
  })
})
