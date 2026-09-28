# Survey: llama-swap on-demand hot-swap for opencode (map #12, ticket #14)

Question: how should `llama-swap` provide on-demand live hot-swap for
opencode on host `two-b`, replacing the wrapper's one-shot `llama-server`?

## Answer (recommended wiring)

Run `llama-swap` persistently on `127.0.0.1:8080`; keep opencode's
`baseURL: http://127.0.0.1:8080/v1` unchanged. One `models:` entry per
`models.json` key; each `cmd` embeds the current wrapper flags with
`--port ${PORT}` (never a hardcoded port). `opencode --model <name>`
then hot-swaps with no wrapper server management.

```yaml
# generated llama-swap config.yaml (sketch)
healthCheckTimeout: 300
globalTTL: 0 # keep loaded; opt-in idle eviction per model later
models:
  "qwen3.8-27b":
    cmd: llama-server --port ${PORT} -hf unsloth/Qwen3.8-27B-GGUF:UD-Q6_K_M --jinja
    checkEndpoint: /health
  "bonsai-27b":
    cmd: llama-server --port ${PORT} -hf prism-ml/Ternary-Bonsai-2-27B-gguf --jinja
    checkEndpoint: /health
```

Nix side (per map prefs): generate this file + `models.json`/`opencode.json`
from Nix options; run swap as a persistent user service; strip the wrapper's
spawn/health-poll/`trap kill` block down to model-name validation + exec.

## Findings

- **Config shape.** `models: { "<id>": { cmd, proxy, checkEndpoint, ttl, ... } }`.
  Minimal viable entry is `cmd` alone; `${PORT}` is auto-assigned per model
  (default range from `startPort: 5800`), and `proxy` defaults to
  `http://localhost:${PORT}`. Verified against `config.example.yaml`.
- **`cmd` vs `hf`.** There is **no `hf:` shortcut at the swap level** — `cmd`
  is an arbitrary shell string. `-hf <repo>[:quant]` stays exactly as today
  because it is a `llama-server` flag (confirmed via local
  `llama-server --help`: `-hf, --hf-repo <user>/<model>[:quant]`).
- **Alias mapping.** Wrapper today: `-a <short_name>` so the single server
  answers as `llama.cpp/<short>`. Under swap the **config key IS the model
  ID**; routing uses the request's `model` field. Options: drop `-a` and let
  the key rule, keep `-a ${MODEL_ID}` for parity, or use `aliases:` /
  `useModelName:` when upstream must see a different name.
- **Eviction.** Default = one model at a time (effective swap-one; `groups` /
  `matrix` DSL opts into concurrency). Idle unload via per-model `ttl` +
  `globalTTL` (both default `0` = never; `-1` inherits global). Manual
  `POST /api/models/unload[/:model_id]`. So "LRU" = swap-one + optional TTL.
- **Health.** Proxy `/health` = "OK" (it is the proxy itself, not a model).
  Per-model readiness = `checkEndpoint` (default `/health`, i.e. llama-server's
  endpoint — the same URL the wrapper curl-polls today) gated by
  `healthCheckTimeout` (default 120s, min 15s). Maps 1:1 onto the wrapper loop.
- **OpenAI-compatible surface.** Proxies `v1/chat/completions`,
  `v1/completions`, `v1/models`, `v1/embeddings`, Anthropic `v1/messages`,
  llama-server extras (`/infill`, `/completion`, `/props?model=`), plus
  `/running`, `/ui`, `/logs[/stream]`, `/metrics`. `GET /v1/models` lists
  config keys — opencode model keys must match (or be `aliases`).
- **opencode routing.** Provider `llama.cpp` (`npm: @ai-sdk/openai-compatible`,
  `baseURL: http://127.0.0.1:8080/v1`) sends `model: "<key>"` to
  `POST /v1/chat/completions`. `opencode --model qwen3.8-27b` resolves to
  `llama.cpp/qwen3.8-27b` via the wrapper + `models.json`, so swap keys must
  equal the `opencode.json` provider `models` keys. No provider-config change
  needed — only what listens on :8080 changes.
- **What stays up.** `llama-swap` (port 8080) persists across
  `opencode --model` switches and opencode restarts; upstream `llama-server`
  children start on first request for their ID and stop on swap/TTL/unload.
  The wrapper's `server_pid` + `trap cleanup EXIT` lifetime ends.

## Consequences / open points (for task tickets, not decided here)

- VRAM fit (`nvidia-smi`) decides TTL vs swap-one vs `matrix` concurrency.
- `--jinja` stays in `cmd` (older llama-server builds need it explicitly).
- HF cache lifecycle, failure UX (load-fail fallback), and `--cloud` path are
  map-level open items (#12) — untouched by this survey.

## Sources

- Local: `llama-swap --help` / `--version` (v249, built 2026-08-10);
  `llama-server --help` (`-hf`, `-a/--alias`, `--port`); nixpkgs
  `llama-swap-249` (MIT, `pkgs/by-name/ll/llama-swap/package.nix`);
  `users/spyro/modules/productivity/llm-agent/{default.nix,opencode-wrapper.sh,models.json,opencode.json}`.
- Upstream: `mostlygeek/llama-swap` README (endpoints, `/health`, `ttl`,
  `matrix`), `docs/configuration.md` (`${PORT}`, `cmd`), `config.example.yaml`
  (`healthCheckTimeout`, `globalTTL`, `checkEndpoint`, `ttl`, `aliases`,
  `useModelName`, `proxy`); opencode docs "Providers" (`@ai-sdk/openai-compatible`,
  `baseURL`, model-key-must-match-`/v1/models`); `ai-sdk.dev` openai-compatible
  provider (`baseURL` + `model-id` routing).
