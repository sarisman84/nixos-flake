import { describe, expect, test } from "bun:test"
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import { handleApi, createServer, type ServerContext } from "./server.js"
import { writeOwnedFile } from "./atomic.js"
import { type Paths } from "./paths.js"

const FIXTURE = readFileSync(new URL("./fixtures/registry.json", import.meta.url), "utf8")

function makeCtx(overrides?: Partial<ServerContext>): {
  ctx: ServerContext
  root: string
  writes: Array<{ path: string; content: string }>
  state: { signals: number }
} {
  const root = mkdtempSync("/tmp/opencode/server-")
  // Lay out the config + state dirs the paths point at.
  mkdirSync(join(root, ".config", "llm-agent"), { recursive: true })
  mkdirSync(join(root, ".config", "llama-swap"), { recursive: true })
  mkdirSync(join(root, ".config", "opencode"), { recursive: true })
  mkdirSync(join(root, ".local", "state", "llm-agent", "leases"), { recursive: true })
  // Seed a valid registry and an opencode.jsonc override.
  writeFileSync(join(root, ".config", "llm-agent", "registry.json"), FIXTURE)
  writeFileSync(join(root, ".config", "opencode", "opencode.jsonc"), '{"plugins":["opencode-skill-creator"]}')

  const paths: Paths = {
    registry: join(root, ".config", "llm-agent", "registry.json"),
    configYaml: join(root, ".config", "llama-swap", "config.yaml"),
    unloadPolicy: join(root, ".config", "llama-swap", "unload-policy.json"),
    opencodeJson: join(root, ".config", "opencode", "opencode.json"),
    opencodeJsonc: join(root, ".config", "opencode", "opencode.jsonc"),
    heartbeat: join(root, ".local", "state", "llm-agent", "heartbeat.json"),
    leaseDir: join(root, ".local", "state", "llm-agent", "leases"),
    backendBase: "http://127.0.0.1:8080",
  }
  const writes: Array<{ path: string; content: string }> = []
  const state = { signals: 0 }
  const ctx: ServerContext = {
    paths,
    opts: {
      llamaServerPath: "/nix/store/llama-cpp/bin/llama-server",
      host: "127.0.0.1",
      port: "8080",
      localProviderId: "llama.cpp",
    },
    writeFile: (path, content) => {
      writes.push({ path, content })
      writeOwnedFile(path, content)
    },
    readFile: (path) => {
      try {
        return readFileSync(path, "utf8")
      } catch {
        return null
      }
    },
    signal: () => {
      state.signals++
      return true
    },
    fetchImpl: (async () => {
      throw new Error("no backend in unit test")
    }) as typeof fetch,
    now: () => 5000,
    isAlive: () => false,
    ...overrides,
  }
  return { ctx, root, writes, state }
}

function cleanup(root: string): void {
  rmSync(root, { recursive: true, force: true })
}

describe("handleApi", () => {
  test("GET /api/registry returns the parsed registry with no errors", async () => {
    const { ctx, root } = makeCtx()
    try {
      const res = await handleApi("GET", "/api/registry", null, ctx)
      expect(res.status).toBe(200)
      const body = JSON.parse(res.body)
      expect(body.errors).toEqual([])
      expect(body.registry.default).toEqual({ provider: "llama.cpp", name: "qwen3-30b-a3b" })
      expect(body.registry.local["qwen3-30b-a3b"].options.ctxSize).toBe(131072)
    } finally {
      cleanup(root)
    }
  })

  test("GET /api/registry reports a missing registry", async () => {
    const { ctx, root } = makeCtx()
    try {
      rmSync(ctx.paths.registry, { force: true })
      const res = await handleApi("GET", "/api/registry", null, ctx)
      const body = JSON.parse(res.body)
      expect(body.registry).toBeNull()
      expect(body.errors).toContain("registry not found")
    } finally {
      cleanup(root)
    }
  })

  test("POST /api/validate reports errors for a bad registry", async () => {
    const { ctx, root } = makeCtx()
    try {
      const bad = FIXTURE.replace('"qwen3-30b-a3b"', '"ghost"')
      const res = await handleApi("POST", "/api/validate", bad, ctx)
      const body = JSON.parse(res.body)
      expect(body.errors.length).toBeGreaterThan(0)
    } finally {
      cleanup(root)
    }
  })

  test("POST /api/preview returns the three generated artefacts", async () => {
    const { ctx, root } = makeCtx()
    try {
      const res = await handleApi("POST", "/api/preview", FIXTURE, ctx)
      expect(res.status).toBe(200)
      const body = JSON.parse(res.body)
      expect(body.ok).toBe(true)
      expect(body.artifacts.configYaml).toContain('"swap":true')
      expect(body.artifacts.opencodeJson).toContain('"model":"llama.cpp/qwen3-30b-a3b"')
      expect(body.artifacts.unloadPolicyJson).toContain('"idleThresholdSeconds":300')
    } finally {
      cleanup(root)
    }
  })

  test("POST /api/apply writes every file and signals a reload", async () => {
    const { ctx, root, writes, state } = makeCtx()
    try {
      const res = await handleApi("POST", "/api/apply", FIXTURE, ctx)
      expect(res.status).toBe(200)
      const body = JSON.parse(res.body)
      expect(body.ok).toBe(true)
      expect(body.message).toBe("applied — running instances pick it up within a second")
      expect(body.reloaded).toBe(true)
      // The generated opencode.json is now a regular file on disk.
      expect(existsSync(ctx.paths.opencodeJson)).toBe(true)
      expect(readFileSync(ctx.paths.opencodeJson, "utf8")).toContain('"model":"llama.cpp/qwen3-30b-a3b"')
      // The opencode.jsonc override is preserved verbatim.
      expect(readFileSync(ctx.paths.opencodeJsonc, "utf8")).toBe('{"plugins":["opencode-skill-creator"]}')
      expect(state.signals).toBe(1)
      expect(writes.length).toBe(5) // registry + 3 generated + jsonc
    } finally {
      cleanup(root)
    }
  })

  test("POST /api/apply refuses an invalid registry and writes nothing", async () => {
    const { ctx, root, writes, state } = makeCtx()
    try {
      const bad = FIXTURE.replace('"qwen3-30b-a3b"', '"ghost"')
      const res = await handleApi("POST", "/api/apply", bad, ctx)
      expect(res.status).toBe(400)
      const body = JSON.parse(res.body)
      expect(body.ok).toBe(false)
      expect(writes).toHaveLength(0)
      expect(state.signals).toBe(0)
    } finally {
      cleanup(root)
    }
  })

  test("GET /api/status reports backend down, no heartbeat, no busy lease", async () => {
    const { ctx, root } = makeCtx()
    try {
      const res = await handleApi("GET", "/api/status", null, ctx)
      const body = JSON.parse(res.body)
      expect(body.backend.up).toBe(false)
      expect(body.heartbeat.present).toBe(false)
      expect(body.leases.busy).toBe(false)
    } finally {
      cleanup(root)
    }
  })

  test("GET /api/status reports a heartbeat age and a busy live lease", async () => {
    const { ctx, root } = makeCtx({
      isAlive: () => true,
      fetchImpl: (async () => {
        throw new Error("down")
      }) as typeof fetch,
    })
    try {
      writeFileSync(ctx.paths.heartbeat, JSON.stringify({ at: 1000, pid: 1, instanceId: "1.a" }))
      writeFileSync(join(ctx.paths.leaseDir, "1.a.json"), JSON.stringify({ instanceId: "1.a", pid: 1, bootId: "b", busySince: 500 }))
      const res = await handleApi("GET", "/api/status", null, ctx)
      const body = JSON.parse(res.body)
      expect(body.heartbeat.present).toBe(true)
      expect(body.heartbeat.ageMs).toBe(4000) // now=5000, at=1000
      expect(body.leases.busy).toBe(true)
      expect(body.leases.busyLeases[0].instanceId).toBe("1.a")
    } finally {
      cleanup(root)
    }
  })

  test("GET /api/export returns the registry with a download header", async () => {
    const { ctx, root } = makeCtx()
    try {
      const res = await handleApi("GET", "/api/export", null, ctx)
      expect(res.status).toBe(200)
      expect(res.headers?.["content-disposition"]).toContain("registry.json")
      expect(res.body).toBe(FIXTURE)
    } finally {
      cleanup(root)
    }
  })

  test("POST /api/import validates before replacing the registry", async () => {
    const { ctx, root } = makeCtx()
    try {
      const bad = FIXTURE.replace('"qwen3-30b-a3b"', '"ghost"')
      const res = await handleApi("POST", "/api/import", bad, ctx)
      expect(res.status).toBe(400)
      // The registry is unchanged.
      expect(readFileSync(ctx.paths.registry, "utf8")).toBe(FIXTURE)
    } finally {
      cleanup(root)
    }
  })

  test("PUT /api/opencode-jsonc writes the override verbatim", async () => {
    const { ctx, root } = makeCtx()
    try {
      const res = await handleApi("PUT", "/api/opencode-jsonc", '{"plugins":["x","y"]}', ctx)
      expect(res.status).toBe(200)
      expect(readFileSync(ctx.paths.opencodeJsonc, "utf8")).toBe('{"plugins":["x","y"]}')
      const get = await handleApi("GET", "/api/opencode-jsonc", null, ctx)
      expect(JSON.parse(get.body).content).toBe('{"plugins":["x","y"]}')
    } finally {
      cleanup(root)
    }
  })

  test("GET /api/opencode-json returns the generated file (null when absent)", async () => {
    const { ctx, root } = makeCtx()
    try {
      let res = await handleApi("GET", "/api/opencode-json", null, ctx)
      expect(JSON.parse(res.body).content).toBeNull()
      writeFileSync(ctx.paths.opencodeJson, '{"model":"x"}')
      res = await handleApi("GET", "/api/opencode-json", null, ctx)
      expect(JSON.parse(res.body).content).toBe('{"model":"x"}')
    } finally {
      cleanup(root)
    }
  })

  test("POST /api/apply names a live busy lease it interrupts", async () => {
    const { ctx, root } = makeCtx({ isAlive: () => true })
    try {
      writeFileSync(
        join(ctx.paths.leaseDir, "1.a.json"),
        JSON.stringify({ instanceId: "1.a", pid: 1, bootId: "b", busySince: 500 }),
      )
      const res = await handleApi("POST", "/api/apply", FIXTURE, ctx)
      expect(res.status).toBe(200)
      const body = JSON.parse(res.body)
      expect(body.ok).toBe(true)
      expect(body.busyLeases).toEqual(["1.a"])
    } finally {
      cleanup(root)
    }
  })

  test("unknown API paths return 404", async () => {
    const { ctx, root } = makeCtx()
    try {
      const res = await handleApi("GET", "/api/nope", null, ctx)
      expect(res.status).toBe(404)
    } finally {
      cleanup(root)
    }
  })
})

describe("createServer (integration)", () => {
  test("serves the API and the UI over real HTTP", async () => {
    const { ctx, root } = makeCtx()
    const uiDir = join(root, "ui")
    mkdirSync(uiDir, { recursive: true })
    writeFileSync(join(uiDir, "index.html"), "<html>llm-agent ui</html>")
    writeFileSync(join(uiDir, "app.js"), "console.log('ui')")
    try {
      const server = createServer(ctx, { port: 0, uiDir })
      const base = `http://127.0.0.1:${server.port}`
      try {
        const reg = await fetch(`${base}/api/registry`)
        expect(reg.status).toBe(200)
        const regBody = (await reg.json()) as { errors: string[] }
        expect(regBody.errors).toEqual([])

        const status = await fetch(`${base}/api/status`)
        expect(status.status).toBe(200)

        const ui = await fetch(`${base}/`)
        expect(ui.status).toBe(200)
        expect(await ui.text()).toBe("<html>llm-agent ui</html>")

        // Static assets are served with the right MIME type.
        const js = await fetch(`${base}/app.js`)
        expect(js.status).toBe(200)
        expect(js.headers.get("content-type")).toBe("text/javascript")

        // Unknown paths fall back to index.html (SPA routing).
        const spa = await fetch(`${base}/some/route`)
        expect(spa.status).toBe(200)
        expect(await spa.text()).toBe("<html>llm-agent ui</html>")
      } finally {
        server.stop()
      }
    } finally {
      cleanup(root)
    }
  })
})
