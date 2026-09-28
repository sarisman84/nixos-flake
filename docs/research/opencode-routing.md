# Research: opencode model picking, routing hooks, backend-follows-picker

Ticket: #27 (part of map #25). Scope: opencode + openai-compatible + llama-swap only.
Local context: `users/spyro/modules/productivity/llm-agent/opencode.json`
(provider `llama.cpp`, `baseURL http://127.0.0.1:8080/v1`), `models.json`, `opencode-wrapper.sh`.

## 1. Provider / model config (what we rely on)

- Custom provider = `provider.<id>` with `npm: "@ai-sdk/openai-compatible"`,
  `options.baseURL`, `models.<id>: { name, limit }`.
  Sources: https://opencode.ai/docs/providers/ (custom-provider + llama.cpp example),
  https://opencode.ai/docs/models/, https://opencode.ai/docs/config/#models
- Map key is the opencode model ID (`llama.cpp/qwen3.8-27b`); per v2 docs the
  wire ID can be overridden with `modelID` (v1 schema in this repo has no
  `modelID` — key IS the wire ID, so it must equal the backend's
  `GET /v1/models` id). Sources: https://opencode.ai/v2/docs/models,
  https://opencode.ai/v2/docs/providers
- `limit.context / limit.output` are local-only hints (compaction budget,
  context accounting), never sent to the server.
- Version gotcha: installed config uses v1 keys
  (`provider`/`npm`/`options`); v2 docs renamed them
  (`providers`/`package`/`settings`). Do not mix. Source:
  https://ofox.io/blog/opencode-api-configuration-guide-2026/
- llama-swap side: extracts `model` from the OpenAI request and on-demand
  loads/swaps the matching upstream; `ttl` evicts; `GET /v1/models`,
  `POST /api/models/load/:id`, `POST /api/models/unload/:id`,
  `GET /api/profiles`, `PUT /api/profiles/active`. Source:
  https://github.com/mostlygeek/llama-swap

## 2. What the `/model` picker drives

- Selector is `providerID/modelID[#variant]` (case-sensitive); picked via
  `/models`, `--model/-m` flag, or `model:` in config.
  Sources: https://opencode.ai/docs/models/#loading-models,
  https://opencode.ai/v2/docs/models
- Selection is **session-scoped** — "switching a session's model does not
  rewrite the config file". Startup priority: `--model` flag > config `model`
  > last used > internal priority.
- The picker drives exactly one thing: the `model` string in the next
  `/v1/chat/completions` body. With llama-swap as `baseURL`, that string IS
  the swap trigger — no opencode restart needed.
- Adjacent natives (not auto-routing): `small_model` (title/compaction
  auxiliary), per-agent `model`, per-command `model`, named `variants` +
  `variant_cycle`. Sources: https://opencode.ai/docs/config/#models,
  https://opencode.ai/docs/agents/
- Config files "normally reload automatically; a model request already in
  progress keeps the settings it started with" (v2 models page).
- Known-risk bug cluster: picker selection can silently revert to the agent
  default after first message / mode switch / resume
  (anomalyco/opencode #23666, #23741, #21351, #23369, #6636 — root cause in
  TUI `local.tsx` model-store sync). Pin manual-selection persistence as a
  validation step for #32.

## 3. Can wrapper / plugin hot-swap backend without restart?

- **Wrapper (`opencode-wrapper.sh`): NO for in-session picks.** It resolves
  `--model/--cloud/default` once at process start, health-checks the backend,
  optionally spawns a single-model `llama-server`, then execs opencode. A
  mid-session `/model` switch to the other local model misses the running
  backend. Keep the wrapper only for process-start duties (env loading,
  cloud-vs-local dispatch, initial server spawn).
- **Plugin: YES, via per-request hooks (no dedicated on-switch hook exists).**
  V1 (installed) hooks: `chat.message` (sees `model.providerID/modelID`),
  `chat.params` / `chat.headers` (mutate options/headers per call),
  `tool.execute.before` (arbitrary `$` shell — can `curl` llama-swap load API
  before dispatch), `event` (`session.created/updated/idle`), `config`
  (rewrite provider catalog at startup). No `model.switched` event exists.
  Sources: https://opencode.ai/docs/plugins/,
  https://cdn.jsdelivr.net/npm/@opencode-ai/plugin@1.3.3/dist/index.d.ts
- V2 equivalents (for future upgrade): `ctx.session.hook("prompt" |
  "context" | "model.request" | "http.request")` + `ctx.catalog.transform`.
  `options` start empty per call; overrides merge provider < model < variant;
  raw body overlays apply after protocol lowering. Source:
  https://opencode.ai/v2/docs/build/plugins
- Practical pattern: stateless pre-request sidecar — on every `chat.params`
  (or `tool.execute.before`) read the requested model id and ensure
  llama-swap has it ready (`POST /api/models/load/:id`, poll `/v1/models`
  state). Works without restart because opencode re-resolves the model each
  turn and config hot-reloads.

## 4. Native prompt-complexity routing? No.

- No built-in complexity scorer, threshold, or auto-switch between local
  models. The only router-like natives are `small_model` (auxiliary tasks),
  per-agent/per-command models (static assignment), variants (manual `#pick`
  or keybind cycle), and cloud Inference Routers (`router:` entries — Zen
  feature, out of scope for local). Source:
  https://opencode.ai/docs/providers/ (Inference Routers section).
- Conclusion for #30: any efficient-vs-reasoning auto-route must live
  **outside** opencode's native model system.

## 5. Routing options, ranked (for #30 / #32)

1. **llama-swap does the swapping (recommended).** One provider,
   `baseURL → llama-swap`, two model entries (`qwen3.8-27b`, `bonsai-27b`)
   with IDs matching swap config. Picker/`--model`/per-agent model selects;
   llama-swap loads/evicts via `ttl`. Zero plugin code, no restart, matches
   map constraint "swap via existing picker, no new UX".
2. **Plugin pre-request sidecar (optional hardening on top of 1).**
   `chat.params` hook + `curl` warm-up/logging around
   `/api/models/load|unload`, `/api/ps`. Pays off only if swap latency or
   VRAM-full behavior (#30) needs explicit control/observability.
3. **Wrapper pre-launch (current, weakest link).** Keep for CLI dispatch, not
   routing — it cannot follow in-session switches by construction.
4. **Separate local router shim (only if #30 demands fully automatic
   routing).** Tiny OpenAI-compatible proxy in front of llama-swap scoring
   complexity and rewriting `model`; opencode sees one entry. Adds a hop and
   a `/v1/models` surface to maintain — redundant while manual picker +
   per-agent defaults suffice.

Explicitly out (per map): vLLM/Ollama/LiteLLM discovery paths, automatic
cloud failover (explicit `--cloud` only).
