# llm-agent model registry

`users/spyro/modules/productivity/llm-agent/models.json` is the single source of truth for local models. `opencode.json` and `config.yaml` are both *generated* from it in `default.nix`; neither is hand-edited.

## Shape

```json
{
  "default": { "provider": "llama.cpp", "name": "qwen3-30b-a3b" },
  "llama.cpp": {
    "<model key>": {
      "displayName": "Shown in the opencode model selector",
      "hfRef": "unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF:UD-Q4_K_XL",
      "options": { "ctxSize": 131072, "outputLimit": 16384 }
    }
  },
  "opencode": { "<cloud model key>": "<value>" }
}
```

The `<model key>` is the **identity on the wire**: it becomes the `model` field opencode sends and must equal the model ID in `config.yaml`. `displayName` is cosmetic and is never transmitted.

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
| `templateOverride` | Chat template file | — |
| `ttl` | Backend-side idle eviction, seconds. `0` = never. Failsafe only | inherit `globalTTL` |
| `mtpProfile` | Multi-Token Prediction tuning; speed XOR context, never implicit | off |
| `extraArgs` | Raw `llama-server` flags | — |

`cacheType` cannot be combined with `cacheTypeK`/`cacheTypeV`. Quantized `cacheTypeV` requires `--flash-attn on`.

## Generated artefacts

| Artefact | Derived from |
|---|---|
| `~/.config/opencode/opencode.json` → `provider."llama.cpp".models` | `llama.cpp` entries; key → model id, `displayName` → `name`, `options` → `limit.context`/`limit.output` |
| `~/.config/opencode/opencode.json` → `model` | `default` |
| `~/.config/llama-swap/config.yaml` → `models` | `llama.cpp` entries; `options` → `llama-server` argv, `ttl` → per-model TTL |
| `~/.config/llama-swap/config.yaml` → `routing` | one **swap group** over all `llama.cpp` keys, one resident at a time |

Adding a model means adding one entry here and rebuilding. No other file needs editing.
