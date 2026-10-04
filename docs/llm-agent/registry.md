# llm-agent model registry

The registry is split across `users/spyro/modules/productivity/llm-agent/`. `opencode.json` and `config.yaml` are both *generated* from these in `default.nix`; neither is hand-edited.

## Layout

| File | Contents |
|---|---|
| `config.json` | the global settings — `default`, `unloadPolicy` — and `models`, the **explicit list** of local model keys to register |
| `models/<key>.json` | one local model per file, named for its key |
| `cloud-models.json` | the cloud model aliases (the old `opencode` section) |

`config.json`:

```json
{
  "default": { "provider": "llama.cpp", "name": "qwen3-30b-a3b" },
  "unloadPolicy": { "idleThresholdSeconds": 300, "settleSeconds": 15 },
  "models": ["qwen3.8-27b", "qwen3.8-27b-200k", "qwen3-30b-a3b", "qwen3-30b-a3b-200k", "qwen3-30b-a3b-ngram", "gpt-oss-20b", "mistral-small-3.2-24b"]
}
```

`models/<key>.json` (one file per registered local model):

```json
{
  "displayName": "Shown in the opencode model selector",
  "hfRef": "unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF:UD-Q4_K_XL",
  "options": { "ctxSize": 131072, "outputLimit": 16384 }
}
```

`cloud-models.json` is a flat map: `{ "<cloud model key>": "<value>" }`.

`default.nix` reads `config.json`, then reads exactly the files named by its `models` list and assembles the `llama.cpp` registry section from them. A key in the list with no file, or a `models/*.json` file whose key is not in the list, fails `nix flake check`.

The `<model key>` is the **identity on the wire**: it is the file name (minus `.json`), becomes the `model` field opencode sends, and must equal the model ID in `config.yaml`. `displayName` is cosmetic and is never transmitted.

`options` fields are all optional — unset values fall back to defaults. Validated by `default.nix` registry assertions; a malformed entry fails `nix flake check` with a readable message.

## `options` fields

| Field | Meaning | Default |
|---|---|---|
| `ctxSize` | Server context window (tokens) | `65536` |
| `outputLimit` | Client-side output budget hint; never sent to the server | `16384` if `ctxSize >= 65536`, else `8192` |
| `gpuLayers` | Layers to offload; `-1` = all | all |
| `cacheTypeK` / `cacheTypeV` | Split KV quantization | `f16` |
| `cacheType` | Shorthand setting both | — |
| `reasoningBudget` | Thinking-token cap; `null` = server default | — |
| `temperature` | Sampling temperature → `--temperature`. Server-side baseline; an agent-level temperature overrides per session | `0.8` |
| `topP` | Nucleus sampling → `--top-p` | `0.95` |
| `topK` | Top-k sampling → `--top-k`; `0` = disabled | `40` |
| `minP` | Min-p sampling → `--min-p`; `0.0` = disabled | `0.05` |
| `templateOverride` | Chat template file | — |
| `ttl` | Backend-side idle eviction, seconds. `0` = never. Failsafe only, set by the unload policy | `120` |
| `specProfile` | Speculative decoding tuning; speed XOR context, never implicit. `specType` is validated against the llama.cpp `--spec-type` list (v0.5.0: draft-*, ngram-*) | off |
| `specProfile.draftModel` / `.draftTokensMax` / `.draftPMin` / `.draftPSplit` / `.draftGpuLayers` / `.draftCacheTypeK` / `.draftCacheTypeV` | Draft-model knobs → `--model-draft`, `--spec-draft-n-max`, `--spec-draft-p-min`, `--spec-draft-p-split`, `--spec-draft-ngl`, `--cache-type-k/v-draft` | server defaults |
| `extraArgs` | Raw `llama-server` flags | — |

`cacheType` cannot be combined with `cacheTypeK`/`cacheTypeV`. Quantized `cacheTypeV` requires `--flash-attn on`.

## Generated artefacts

| Artefact | Derived from |
|---|---|
| `~/.config/opencode/opencode.json` → `provider."llama.cpp".models` | `llama.cpp` entries; key → model id, `displayName` → `name`, `options` → `limit.context`/`limit.output` |
| `~/.config/opencode/opencode.json` → `model` | `default` |
| `~/.config/llama-swap/config.yaml` → `models` | `llama.cpp` entries; `options` → `llama-server` argv, `ttl` → per-model TTL |
| `~/.config/llama-swap/config.yaml` → `routing` | one **swap group** over all `llama.cpp` keys, one resident at a time |
| `~/.config/opencode/plugins/llm-agent-unload.ts` | the unload policy, as one self-contained file |
| `~/.config/llama-swap/unload-policy.json` | `unloadPolicy` thresholds + the backend URL |

The unload thresholds are registry data rather than code constants, so retuning
is an edit to `config.json`. `nix flake check` rejects an `unloadPolicy` that is
missing, mistyped, or carries an unknown field.

The plugin is deployed as a single self-contained file: `home.file.<name>.text` flattens each file to its own store path, so a relative import in the deployed copy would resolve against `/nix/store` and fail silently. The seam stays authored separately in `policy/decision.ts` and is spliced in at build time; `nix flake check` asserts the splice stayed sound, and the deployed file exports exactly one function (opencode invokes every function export as a plugin factory).

`config.yaml` is emitted with `builtins.toJSON`. JSON is a subset of YAML, so the
result is valid YAML, but do not expect YAML formatting or comments in the
generated file. Its shape is asserted by `nix flake check` — the one-resident
guarantee is a build-time check, not a runtime hope.

Adding a model means adding a `models/<key>.json` file, adding its key to `config.json`'s `models` list, and rebuilding. `nix flake check` fails if the two are out of sync. Which values to set — and why — is covered in [tuning.md](./tuning.md).
