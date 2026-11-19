/**
 * The `llm-agent serve` entrypoint: resolve the paths, wire the real side
 * effects (file writes, the systemctl reload, the backend fetch, the liveness
 * probe), and start the loopback server.
 *
 * The pure orchestration lives in `server.ts`/`apply.ts` (tested); this module
 * only provides the concrete dependencies and the process entry.
 */
import { readFileSync } from "node:fs"
import { spawnSync } from "node:child_process"
import { join } from "node:path"
import { defaultPaths, type Paths } from "./paths.js"
import { writeOwnedFile } from "./atomic.js"
import { isProcessAlive } from "./status.js"
import { createServer, type ServerContext } from "./server.js"

const HOSTNAME = "127.0.0.1"
const DEFAULT_PORT = 8090
const BACKEND_HOST = "127.0.0.1"
const BACKEND_PORT = "8080"
const LOCAL_PROVIDER = "llama.cpp"

/** Send the backend reload signal: a SIGHUP (reload, not restart). */
export function signalLlamaSwap(): boolean {
  const res = spawnSync("systemctl", ["--user", "kill", "-s", "HUP", "llama-swap"])
  return res.status === 0
}

/** Read a file's content, or `null` when it does not exist. */
export function readFileOrNull(path: string): string | null {
  try {
    return readFileSync(path, "utf8")
  } catch {
    return null
  }
}

/**
 * Detect the `llama-server` binary path from the existing (flake-generated)
 * `config.yaml`: it is the first token of any model's `cmd`. Falls back to the
 * `LLM_AGENT_LLAMA_SERVER` env var, then a placeholder.
 */
export function detectLlamaServerPath(paths: Paths, env: { [k: string]: string | undefined }): string {
  const text = readFileOrNull(paths.configYaml)
  if (text) {
    // The cmd is a JSON string like "<path> --port ${PORT} -hf ...".
    const match = text.match(/"cmd"\s*:\s*"([^"]+)"/)
    if (match) {
      const first = match[1].split(" ")[0]
      if (first && first !== "${PORT}") return first
    }
  }
  return env.LLM_AGENT_LLAMA_SERVER ?? "/nix/store/llama-cpp/bin/llama-server"
}

/**
 * The built UI directory. In a compiled binary the build embeds it under
 * `/$bunfs/root/ui/dist`; in dev (running from the repo) it is `ui/dist` next
 * to this module. `LLM_AGENT_UI_DIR` overrides both.
 */
export function uiDir(): string | null {
  const fromEnv = process.env.LLM_AGENT_UI_DIR
  if (fromEnv) return fromEnv
  // Compiled binary: `--asset ui/dist` embeds the directory under its basename,
  // so the UI lives at /$bunfs/root/dist.
  try {
    readFileSync("/$bunfs/root/dist/index.html", "utf8")
    return "/$bunfs/root/dist"
  } catch {
    // Not a compiled binary with an embedded UI.
  }
  // Dev: ui/dist next to this module.
  const candidate = join(import.meta.dir, "ui", "dist")
  try {
    readFileSync(join(candidate, "index.html"), "utf8")
    return candidate
  } catch {
    return null
  }
}

/** Build the concrete server context from the live environment. */
export function makeContext(): ServerContext {
  const paths = defaultPaths()
  return {
    paths,
    opts: {
      llamaServerPath: detectLlamaServerPath(paths, process.env),
      host: BACKEND_HOST,
      port: BACKEND_PORT,
      localProviderId: LOCAL_PROVIDER,
    },
    writeFile: writeOwnedFile,
    readFile: readFileOrNull,
    signal: signalLlamaSwap,
    fetchImpl: fetch,
    now: () => Date.now(),
    isAlive: isProcessAlive,
  }
}

/** Start the server and block until it is stopped. */
export function serve(): void {
  const port = Number(process.env.LLM_AGENT_PORT ?? DEFAULT_PORT)
  const ctx = makeContext()
  const server = createServer(ctx, { hostname: HOSTNAME, port, uiDir: uiDir() })
  console.log(`llm-agent serving on http://${HOSTNAME}:${server.port}`)
  console.log(`  registry: ${ctx.paths.registry}`)
}

// Run when executed directly (not when imported by a test). The binary is the
// `llm-agent` command; `serve` (the default) starts the server.
if (import.meta.main) {
  const cmd = process.argv[2] ?? "serve"
  if (cmd === "serve") {
    serve()
  } else {
    console.error(`llm-agent: unknown command '${cmd}' (expected 'serve')`)
    process.exit(1)
  }
}
