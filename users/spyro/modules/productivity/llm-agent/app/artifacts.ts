/**
 * Build the generated artefacts from a validated registry.
 *
 * Three of the four files the apply step writes are *generated* from the
 * registry by the #92 core (`generate.ts`): the llama-swap `config.yaml`, the
 * `opencode.json`, and the `unload-policy.json`. They are serialized with
 * `toNixJson` (Nix `toJSON` semantics) so they match the flake's output
 * byte-for-byte — no trailing newline, keys sorted, floats to six decimals.
 *
 * The fourth file, `opencode.jsonc`, is NOT generated here: it is a user-owned
 * override document (it loads after `opencode.json` and wins for shared keys),
 * so the app reads and writes it as-is rather than deriving it from the
 * registry.
 */
import {
  generateOpencodeConfig,
  generateSwapConfig,
  generateUnloadPolicy,
  toNixJson,
} from "./generate.js"
import { type Registry } from "./registry.js"

/** The three registry-generated artefacts, ready to write to disk. */
export interface Artifacts {
  configYaml: string
  opencodeJson: string
  unloadPolicyJson: string
}

/** The inputs the generators need beyond the registry. */
export interface ArtifactOpts {
  /** Stands in for the flake's `${pkgs.llama-cpp}/bin/llama-server`. */
  llamaServerPath: string
  host: string
  port: string
  localProviderId: string
}

export function buildArtifacts(registry: Registry, opts: ArtifactOpts): Artifacts {
  return {
    configYaml: toNixJson(generateSwapConfig(registry, { llamaServerPath: opts.llamaServerPath })),
    opencodeJson: toNixJson(generateOpencodeConfig(registry)),
    unloadPolicyJson: toNixJson(
      generateUnloadPolicy(registry, {
        host: opts.host,
        port: opts.port,
        localProviderId: opts.localProviderId,
      }),
    ),
  }
}
