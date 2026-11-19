/**
 * The on-disk locations the app reads and writes, resolved from the home
 * directory and the relevant environment variables.
 *
 * The config files live under `~/.config` (the home-manager layout the flake
 * writes), while the per-user state (heartbeat, leases) lives under
 * `$XDG_STATE_HOME/llm-agent` or `~/.local/state/llm-agent` — matching the
 * unload-policy plugin's `stateDir()`. Keeping the resolution pure (env in,
 * paths out) makes it testable without touching the real filesystem.
 */
import { join } from "node:path"

/** Every path the server needs, resolved once at start. */
export interface Paths {
  /** The single-file registry the app owns end to end. */
  registry: string
  /** The generated llama-swap `config.yaml`. */
  configYaml: string
  /** The generated `unload-policy.json`. */
  unloadPolicy: string
  /** The generated `opencode.json` (the app owns it as a regular file). */
  opencodeJson: string
  /** The user-owned `opencode.jsonc` override (loads last, wins for shared keys). */
  opencodeJsonc: string
  /** The unload-policy plugin's heartbeat. */
  heartbeat: string
  /** The unload-policy plugin's lease directory. */
  leaseDir: string
  /** The llama-swap backend base URL (loopback, no auth). */
  backendBase: string
}

/** The environment the paths are resolved from. */
export interface PathEnv {
  home: string
  xdgStateHome?: string
  backendHost?: string
  backendPort?: string
}

export function resolvePaths(env: PathEnv): Paths {
  const configDir = join(env.home, ".config")
  const stateDir = env.xdgStateHome ?? join(env.home, ".local", "state")
  const host = env.backendHost ?? "127.0.0.1"
  const port = env.backendPort ?? "8080"
  return {
    registry: join(configDir, "llm-agent", "registry.json"),
    configYaml: join(configDir, "llama-swap", "config.yaml"),
    unloadPolicy: join(configDir, "llama-swap", "unload-policy.json"),
    opencodeJson: join(configDir, "opencode", "opencode.json"),
    opencodeJsonc: join(configDir, "opencode", "opencode.jsonc"),
    heartbeat: join(stateDir, "llm-agent", "heartbeat.json"),
    leaseDir: join(stateDir, "llm-agent", "leases"),
    backendBase: `http://${host}:${port}`,
  }
}

/** Resolve the paths from the live environment (the server's default). */
export function defaultPaths(): Paths {
  return resolvePaths({
    home: process.env.HOME ?? "",
    xdgStateHome: process.env.XDG_STATE_HOME,
    backendHost: process.env.LLM_AGENT_BACKEND_HOST,
    backendPort: process.env.LLM_AGENT_BACKEND_PORT,
  })
}
