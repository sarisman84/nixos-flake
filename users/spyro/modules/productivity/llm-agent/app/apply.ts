/**
 * The apply flow: validate the registry, build the generated artefacts, write
 * every file the app owns, and reload the backend.
 *
 * The side effects (writing files, signalling the backend) are injected so the
 * orchestration is testable without touching the real filesystem or systemd.
 * The server wires in `writeOwnedFile` (which replaces the Nix-store symlinks
 * with regular files the app owns) and a `systemctl --user kill -s HUP
 * llama-swap` reload.
 */
import { toNixJson } from "./generate.js"
import { type Json } from "./json.js"
import { buildArtifacts, type ArtifactOpts, type Artifacts } from "./artifacts.js"
import { type Paths } from "./paths.js"
import { toRegistry, validateRegistry } from "./registry.js"

/** The outcome of an apply (or staged save). */
export interface ApplyResult {
  ok: boolean
  errors: string[]
  /** The pick-up message, present on success. */
  message?: string
  /** The generated artefacts, present on success. */
  artifacts?: Artifacts
  /** The files that were written. */
  wrote: string[]
  /** Whether the backend reload signal was sent (and succeeded). */
  reloaded: boolean
}

/** The injected side effects. */
export interface ApplyDeps {
  paths: Paths
  opts: ArtifactOpts
  /**
   * The `opencode.jsonc` content to write, or `null` to leave the file alone.
   * It is user-owned (not generated from the registry), so the caller decides
   * whether to touch it.
   */
  opencodeJsonc: string | null
  /** Write a file as a regular file the app owns (replacing any symlink). */
  writeFile: (path: string, content: string) => void
  /** Send the backend reload signal; returns true on success. */
  signal: () => boolean
}

/**
 * Validate the registry and return the failure result, or `null` when it is
 * valid. Shared by the staged save and the full apply so the guard lives in
 * one place.
 */
function validationFailure(reg: { [key: string]: Json }): ApplyResult | null {
  const errors = validateRegistry(reg)
  return errors.length > 0 ? { ok: false, errors, wrote: [], reloaded: false } : null
}

/**
 * Staged save: validate and write only the registry file. Does not regenerate
 * the artefacts or signal the backend — that is what `applyRegistry` does.
 */
export function saveRegistry(reg: { [key: string]: Json }, deps: ApplyDeps): ApplyResult {
  const failure = validationFailure(reg)
  if (failure) return failure
  deps.writeFile(deps.paths.registry, toNixJson(reg))
  return { ok: true, errors: [], wrote: [deps.paths.registry], reloaded: false }
}

/**
 * Apply: validate, write the registry and every generated artefact (plus the
 * `opencode.jsonc` override when provided), then reload the backend with a
 * SIGHUP (not a restart). On validation failure nothing is written and no
 * signal is sent.
 */
export function applyRegistry(reg: { [key: string]: Json }, deps: ApplyDeps): ApplyResult {
  const failure = validationFailure(reg)
  if (failure) return failure
  const registry = toRegistry(reg)
  const artifacts = buildArtifacts(registry, deps.opts)
  const wrote: string[] = []

  // The registry is the source of truth; write it first.
  deps.writeFile(deps.paths.registry, toNixJson(reg))
  wrote.push(deps.paths.registry)

  // The generated artefacts, each as a regular file the app owns.
  deps.writeFile(deps.paths.configYaml, artifacts.configYaml)
  wrote.push(deps.paths.configYaml)
  deps.writeFile(deps.paths.opencodeJson, artifacts.opencodeJson)
  wrote.push(deps.paths.opencodeJson)
  deps.writeFile(deps.paths.unloadPolicy, artifacts.unloadPolicyJson)
  wrote.push(deps.paths.unloadPolicy)

  // The user-owned override, only when the caller provided content.
  if (deps.opencodeJsonc !== null) {
    deps.writeFile(deps.paths.opencodeJsonc, deps.opencodeJsonc)
    wrote.push(deps.paths.opencodeJsonc)
  }

  // Reload the backend so it re-reads config.yaml. A SIGHUP reload (not a
  // restart): it evicts the resident model exactly like a restart would, which
  // the confirmation message must say.
  const reloaded = deps.signal()

  return {
    ok: true,
    errors: [],
    message: "applied — running instances pick it up within a second",
    artifacts,
    wrote,
    reloaded,
  }
}
