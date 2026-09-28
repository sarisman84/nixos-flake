# PROTOTYPE sketch: adaptive local JSON + swap flow (ticket #32)

Throwaway. Answers "what should the config look like, and how does a swap behave".
Branch: `prototype/sketch-adaptive-json`. No production code; nothing here runs.

## Files

- `models.json` — both entries under the locked #31 schema.
- `opencode.delta.json` — fragments to merge into `opencode.json`.
- (llama-swap side sketched below as YAML, not a file — it lives outside this repo at `~/.config/llama-swap/config.yaml`.)

## Swap flow (measured numbers from #29)

1. User picks via opencode `/model` picker (or `--model`, per-agent default). Default session model: `llama.cpp/qwen3.8-27b`.
2. Opencode sends `model: "qwen3.8-27b"` (v1 schema: key IS the wire ID) to `baseURL → llama-swap :8080`.
3. llama-swap matches upstream, evicts resident if different (`swap: true, exclusive: true`, one resident), loads target. Measured: ~4s cold load, ~3s unload.
4. Idle eviction by per-model `ttl` (reasoning 0 = never, efficient 600s). Over-limit concurrent-model pressure → HTTP 429, client queues; cloud never automatic.
5. `small_model` (titles/compaction) pinned to `llama.cpp/qwen3-8b`.

## llama-swap sketch (mirrors models.json options)

```yaml
healthCheckTimeout: 300
globalTTL: 0
routing:
  router:
    use: group
    settings:
      groups:
        local-llms:
          swap: true
          exclusive: true
          members: ["qwen3.8-27b", "qwen3-8b"]
models:
  qwen3.8-27b:
    ttl: 0
    cmd: llama-server --port ${PORT} -hf unsloth/Qwen3.8-27B-GGUF:UD-Q6_K_M --jinja --ctx-size 131072 --cache-type-k q4_0 --cache-type-v q4_0 --flash-attn on --reasoning-budget 2048
  qwen3-8b:
    ttl: 600
    cmd: llama-server --port ${PORT} -hf unsloth/Qwen3-8B-GGUF:UD-Q4_K_XL --jinja --ctx-size 32768 --cache-type-k q4_0 --cache-type-v q4_0 --flash-attn on --reasoning-budget 0
```

## Open questions for reaction (answer to resolve #32)

1. `--flash-attn on` currently rides in `extraArgs`. First-class `flashAttn: bool` instead?
2. `limit.output` values (16384 / 8192) are invented here — keep, tune, or drop output caps entirely?
3. 200k opt-in for reasoning: second model entry (e.g. `qwen3.8-27b-200k`) or a documented manual `ctxSize` override?
4. Efficient non-thinking enforced via `reasoningBudget: 0` — acceptable proxy, or must the wrapper also pass `/no_think` per request?
5. Keep `default` on reasoning, or default to efficient with escalation to reasoning?
