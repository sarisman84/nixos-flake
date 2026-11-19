/**
 * The bun HTTP server: a loopback-only JSON API plus the bundled UI.
 *
 * The route handlers are pure functions of (method, path, body, context) so
 * they are testable without a live socket; `createServer` wires them to
 * `Bun.serve`. The context carries the injected side effects (file writes, the
 * backend reload signal, the fetch used to poll the backend, the clock, and the
 * liveness probe) so the handlers never touch the real filesystem or systemd
 * directly.
 */
import { readFileSync } from "node:fs"
import { join, normalize, resolve } from "node:path"
import { type Json, NixNum, parseNixJson } from "./json.js"
import { toRegistry, validateRegistry } from "./registry.js"
import { buildArtifacts, type ArtifactOpts } from "./artifacts.js"
import { applyRegistry, saveRegistry, type ApplyDeps } from "./apply.js"
import { type Paths } from "./paths.js"
import {
  fetchBackendStatus,
  readHeartbeat,
  readLeaseStatus,
} from "./status.js"

/** Convert the parsed (NixNum) registry to a plain JSON-serializable value. */
export function toJson(v: Json): unknown {
  if (v === null || typeof v === "string" || typeof v === "boolean") return v
  if (v instanceof NixNum) return v.value
  if (Array.isArray(v)) return v.map(toJson)
  if (typeof v === "object") {
    const out: Record<string, unknown> = {}
    for (const [k, val] of Object.entries(v)) out[k] = toJson(val)
    return out
  }
  return v
}

/** The injected dependencies the handlers need. */
export interface ServerContext {
  paths: Paths
  opts: ArtifactOpts
  /** Write a file as a regular file the app owns (replacing any symlink). */
  writeFile: (path: string, content: string) => void
  /** Read a file's content, or `null` when it does not exist. */
  readFile: (path: string) => string | null
  /** Send the backend reload signal; returns true on success. */
  signal: () => boolean
  /** The fetch used to poll the backend (injected so tests can fake it). */
  fetchImpl: typeof fetch
  /** The clock, for the heartbeat age. */
  now: () => number
  /** The liveness probe for the lease set. */
  isAlive: (pid: number, bootId: string | null) => boolean
}

export interface ApiResponse {
  status: number
  body: string
  headers?: Record<string, string>
}

function json(value: unknown, status = 200): ApiResponse {
  return { status, body: JSON.stringify(value), headers: { "content-type": "application/json" } }
}

function parseBody(rawBody: string | null):
  | { ok: true; reg: { [key: string]: Json } }
  | { ok: false; errors: string[] } {
  if (rawBody === null || rawBody.trim() === "") {
    return { ok: false, errors: ["request body is empty"] }
  }
  try {
    return { ok: true, reg: parseNixJson(rawBody) as { [key: string]: Json } }
  } catch (error) {
    return { ok: false, errors: [`invalid JSON: ${String(error)}`] }
  }
}

function makeDeps(ctx: ServerContext, opencodeJsonc: string | null): ApplyDeps {
  return { paths: ctx.paths, opts: ctx.opts, opencodeJsonc, writeFile: ctx.writeFile, signal: ctx.signal }
}

// --- handlers ----------------------------------------------------------------

function handleGetRegistry(ctx: ServerContext): ApiResponse {
  const text = ctx.readFile(ctx.paths.registry)
  if (text === null) {
    return json({ registry: null, errors: ["registry not found"] })
  }
  let parsed: { [key: string]: Json }
  try {
    parsed = parseNixJson(text) as { [key: string]: Json }
  } catch (error) {
    return json({ registry: null, errors: [`registry: invalid JSON: ${String(error)}`] })
  }
  return json({ registry: toJson(parsed), errors: validateRegistry(parsed) })
}

function handlePutRegistry(rawBody: string | null, ctx: ServerContext): ApiResponse {
  const parsed = parseBody(rawBody)
  if (!parsed.ok) return json({ ok: false, errors: parsed.errors }, 400)
  const result = saveRegistry(parsed.reg, makeDeps(ctx, null))
  return json({ ok: result.ok, errors: result.errors, wrote: result.wrote }, result.ok ? 200 : 400)
}

function handleValidate(rawBody: string | null, ctx: ServerContext): ApiResponse {
  const parsed = parseBody(rawBody)
  if (!parsed.ok) return json({ errors: parsed.errors }, 400)
  return json({ errors: validateRegistry(parsed.reg) })
}

function handlePreview(rawBody: string | null, ctx: ServerContext): ApiResponse {
  const parsed = parseBody(rawBody)
  if (!parsed.ok) return json({ ok: false, errors: parsed.errors }, 400)
  const errors = validateRegistry(parsed.reg)
  if (errors.length > 0) return json({ ok: false, errors }, 400)
  const artifacts = buildArtifacts(toRegistry(parsed.reg), ctx.opts)
  return json({ ok: true, artifacts })
}

async function handleStatus(ctx: ServerContext): Promise<ApiResponse> {
  const backend = await fetchBackendStatus(ctx.paths.backendBase, ctx.fetchImpl)
  const heartbeat = readHeartbeat(ctx.paths.heartbeat, ctx.now())
  const leases = readLeaseStatus(ctx.paths.leaseDir, ctx.isAlive)
  return json({ backend, heartbeat, leases })
}

function handleApply(rawBody: string | null, ctx: ServerContext): ApiResponse {
  const parsed = parseBody(rawBody)
  if (!parsed.ok) return json({ ok: false, errors: parsed.errors }, 400)
  // Preserve the user-owned opencode.jsonc override (read from disk).
  const jsonc = ctx.readFile(ctx.paths.opencodeJsonc)
  const result = applyRegistry(parsed.reg, makeDeps(ctx, jsonc))
  // The busy-lease check, at the API level: name any live busy lease that the
  // reload just interrupted, so a client bypassing the UI still hears about it
  // concretely (the UI gates on the same state via /api/status).
  const leases = readLeaseStatus(ctx.paths.leaseDir, ctx.isAlive)
  return json(
    {
      ok: result.ok,
      errors: result.errors,
      message: result.message,
      reloaded: result.reloaded,
      wrote: result.wrote,
      ...(leases.busy ? { busyLeases: leases.busyLeases.map((l) => l.instanceId) } : {}),
    },
    result.ok ? 200 : 400,
  )
}

function handleExport(ctx: ServerContext): ApiResponse {
  const text = ctx.readFile(ctx.paths.registry)
  if (text === null) return json({ error: "registry not found" }, 404)
  return {
    status: 200,
    body: text,
    headers: {
      "content-type": "application/json",
      "content-disposition": 'attachment; filename="registry.json"',
    },
  }
}

function handleImport(rawBody: string | null, ctx: ServerContext): ApiResponse {
  const parsed = parseBody(rawBody)
  if (!parsed.ok) return json({ ok: false, errors: parsed.errors }, 400)
  const errors = validateRegistry(parsed.reg)
  if (errors.length > 0) return json({ ok: false, errors }, 400)
  // A valid import replaces the registry (a staged save, not an apply).
  const result = saveRegistry(parsed.reg, makeDeps(ctx, null))
  return json({ ok: result.ok, errors: result.errors, wrote: result.wrote }, result.ok ? 200 : 400)
}

function handleGetJsonc(ctx: ServerContext): ApiResponse {
  const text = ctx.readFile(ctx.paths.opencodeJsonc)
  return json({ content: text })
}

/** The generated opencode.json currently on disk (read-only in the UI). */
function handleGetOpencodeJson(ctx: ServerContext): ApiResponse {
  const text = ctx.readFile(ctx.paths.opencodeJson)
  return json({ content: text })
}

function handlePutJsonc(rawBody: string | null, ctx: ServerContext): ApiResponse {
  if (rawBody === null) return json({ ok: false, errors: ["request body is empty"] }, 400)
  // The override is user-owned; the app writes it verbatim (it is not
  // validated against the registry schema).
  ctx.writeFile(ctx.paths.opencodeJsonc, rawBody)
  return json({ ok: true, wrote: [ctx.paths.opencodeJsonc] })
}

/**
 * Route an API request. Returns the JSON response; the UI (non-`/api` paths)
 * is served by `createServer`, not here.
 */
export async function handleApi(
  method: string,
  pathname: string,
  rawBody: string | null,
  ctx: ServerContext,
): Promise<ApiResponse> {
  if (pathname === "/api/registry") {
    if (method === "GET") return handleGetRegistry(ctx)
    if (method === "PUT") return handlePutRegistry(rawBody, ctx)
  } else if (pathname === "/api/validate" && method === "POST") {
    return handleValidate(rawBody, ctx)
  } else if (pathname === "/api/preview" && method === "POST") {
    return handlePreview(rawBody, ctx)
  } else if (pathname === "/api/status" && method === "GET") {
    return handleStatus(ctx)
  } else if (pathname === "/api/apply" && method === "POST") {
    return handleApply(rawBody, ctx)
  } else if (pathname === "/api/export" && method === "GET") {
    return handleExport(ctx)
  } else if (pathname === "/api/import" && method === "POST") {
    return handleImport(rawBody, ctx)
  } else if (pathname === "/api/opencode-jsonc") {
    if (method === "GET") return handleGetJsonc(ctx)
    if (method === "PUT") return handlePutJsonc(rawBody, ctx)
  } else if (pathname === "/api/opencode-json" && method === "GET") {
    return handleGetOpencodeJson(ctx)
  }
  return json({ error: "not found" }, 404)
}

/** The MIME type for a static asset by extension. */
function mimeFor(path: string): string {
  const ext = path.slice(path.lastIndexOf(".") + 1).toLowerCase()
  switch (ext) {
    case "html":
      return "text/html"
    case "js":
      return "text/javascript"
    case "css":
      return "text/css"
    case "json":
      return "application/json"
    case "svg":
      return "image/svg+xml"
    case "png":
      return "image/png"
    case "ico":
      return "image/x-icon"
    default:
      return "application/octet-stream"
  }
}

/**
 * Read a UI asset from `uiDir`, guarding against path traversal. Returns the
 * file content, or `null` when the file does not exist or the path escapes
 * `uiDir`.
 */
function readUiFile(uiDir: string, relPath: string): string | null {
  const clean = normalize(relPath).replace(/^([/\\])+/, "")
  const full = resolve(join(uiDir, clean))
  const root = resolve(uiDir)
  if (full !== root && !full.startsWith(root + "/")) return null
  try {
    return readFileSync(full, "utf8")
  } catch {
    return null
  }
}

/**
 * Start the server on `hostname:port` (loopback by default) and serve the API
 * plus the bundled UI. `uiDir` is the built UI directory (Vite's `dist/`); when
 * it is `null` the UI is not served (API-only, used by the tests). Non-API
 * paths fall back to `index.html` so the SPA can use client-side routing.
 */
export function createServer(
  ctx: ServerContext,
  opts: { hostname?: string; port: number; uiDir?: string | null },
): BunServer {
  return Bun.serve({
    hostname: opts.hostname ?? "127.0.0.1",
    port: opts.port,
    fetch: async (req: Request) => {
      const url = new URL(req.url)
      if (url.pathname.startsWith("/api/")) {
        const rawBody = req.method === "GET" ? null : await req.text()
        const res = await handleApi(req.method, url.pathname, rawBody, ctx)
        return new Response(res.body, { status: res.status, headers: res.headers })
      }
      if (opts.uiDir) {
        const rel = url.pathname === "/" ? "/index.html" : url.pathname
        const file = readUiFile(opts.uiDir, rel)
        if (file !== null) {
          return new Response(file, { status: 200, headers: { "content-type": mimeFor(rel) } })
        }
        // SPA fallback: serve index.html for unknown paths.
        const index = readUiFile(opts.uiDir, "/index.html")
        if (index !== null) {
          return new Response(index, { status: 200, headers: { "content-type": "text/html" } })
        }
      }
      return new Response("llm-agent", { status: 200, headers: { "content-type": "text/plain" } })
    },
  })
}
