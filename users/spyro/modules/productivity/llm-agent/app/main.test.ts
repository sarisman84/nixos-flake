import { describe, expect, test } from "bun:test"
import { mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import { detectLlamaServerPath, readFileOrNull } from "./main.js"
import { type Paths } from "./paths.js"

function scratch(): string {
  return mkdtempSync("/tmp/opencode/main-")
}

function pathsIn(root: string): Paths {
  return {
    registry: join(root, "registry.json"),
    configYaml: join(root, "config.yaml"),
    unloadPolicy: join(root, "unload-policy.json"),
    opencodeJson: join(root, "opencode.json"),
    opencodeJsonc: join(root, "opencode.jsonc"),
    heartbeat: join(root, "heartbeat.json"),
    leaseDir: join(root, "leases"),
    backendBase: "http://127.0.0.1:8080",
  }
}

describe("readFileOrNull", () => {
  test("returns the content for an existing file", () => {
    const root = scratch()
    try {
      const p = join(root, "f.txt")
      writeFileSync(p, "hello")
      expect(readFileOrNull(p)).toBe("hello")
    } finally {
      rmSync(root, { recursive: true, force: true })
    }
  })

  test("returns null for a missing file", () => {
    expect(readFileOrNull("/tmp/opencode/does-not-exist-xyz")).toBeNull()
  })
})

describe("detectLlamaServerPath", () => {
  test("extracts the path from the first model cmd in config.yaml", () => {
    const root = scratch()
    try {
      const paths = pathsIn(root)
      writeFileSync(
        paths.configYaml,
        '{"models":{"m1":{"cmd":"/nix/store/abc/bin/llama-server --port ${PORT} -hf owner/repo:q"}}}',
      )
      expect(detectLlamaServerPath(paths, {})).toBe("/nix/store/abc/bin/llama-server")
    } finally {
      rmSync(root, { recursive: true, force: true })
    }
  })

  test("falls back to the env var when no config.yaml", () => {
    const root = scratch()
    try {
      const paths = pathsIn(root)
      expect(detectLlamaServerPath(paths, { LLM_AGENT_LLAMA_SERVER: "/custom/llama-server" })).toBe(
        "/custom/llama-server",
      )
    } finally {
      rmSync(root, { recursive: true, force: true })
    }
  })

  test("falls back to the default when neither is available", () => {
    const root = scratch()
    try {
      const paths = pathsIn(root)
      expect(detectLlamaServerPath(paths, {})).toBe("/nix/store/llama-cpp/bin/llama-server")
    } finally {
      rmSync(root, { recursive: true, force: true })
    }
  })
})
