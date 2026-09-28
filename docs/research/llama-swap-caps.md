# Research: llama-swap lazy-load, TTL eviction, hot-swap API

Ticket: #26 (map #25). Scope: llama-swap docs + source only. No code changes.
Date: 2026-09-28. Upstream: `mostlygeek/llama-swap` (main branch).

## 1. Lazy-load (on-demand, no VRAM pre-allocation)

- Default behavior: nothing runs at startup. First OpenAI-compatible request
  carrying `"model": "<id>"` starts that model's `cmd` and proxies once its
  `checkEndpoint` returns 200. Source: README swap description +
  `docs/config.example.yaml` (`checkEndpoint`, default `/health`).
- Opt-out of lazy-load: `hooks.on_startup.preload: ["<id>", ...]` warms models
  at boot (released v151, issue #209 / PR #235). Preloading >1 model in a
  `swap: true` group thrashes — put co-resident models in a `swap: false` group.
- Per-request routing keys: `model` field in `v1/chat/completions`,
  `v1/completions`, `v1/embeddings`, audio/image endpoints. `/upstream/:model`
  addresses one upstream directly. `/v1/models` lists IDs (+ aliases if
  `includeAliasesInList: true`).
- Health gate: `healthCheckTimeout` (default 120s, min 15s). Requests block
  until healthy or fail. `sendLoadingState: true` streams "loading" status in
  the thinking/reasoning field while a swap warms (issue #366).
- Sources:
  - https://github.com/mostlygeek/llama-swap
  - https://raw.githubusercontent.com/mostlygeek/llama-swap/main/docs/config.example.yaml
  - https://github.com/mostlygeek/llama-swap/discussions/209

## 2. TTL / idle eviction

| Key | Scope | Default | Semantics |
|---|---|---|---|
| `globalTTL` | top-level | `0` | Default idle seconds before unload; `0` = never auto-unload; must be `>= 0` |
| `models.<id>.ttl` | per-model | `-1` | `-1` = inherit `globalTTL`; `0` = never unload; `>0` = unload after N idle seconds |
| `unloadTimeout` / `models.<id>.unloadTimeout` | global/per-model | `10` | Graceful SIGTERM window before SIGKILL on TTL/API/manual unload |
| `hooks` `on_startup.preload` | boot | `[]` | Only preload hook; no `after_expire`/`after_unload` auto-reload in stable release (proposed in #209 discussion only) |

- TTL resets on activity; websocket connections can be excluded via
  `models.<id>.compat.ignoreWebsockets: true` (else they hold TTL/swap).
- Eviction = process stop (`cmdStop` or SIGTERM → SIGKILL after
  `unloadTimeout`). No KV-cache snapshot/restore; next request pays full cold
  start (weights reload + prompt processing).
- Recommended starting point for this stack (2× 27B, one resident):
  `globalTTL: 0` + per-model `ttl: 300-600` on the cold model, `ttl: 0` on the
  hot/default model. Tune after ticket #29 measures swap latency.
- Source: `docs/config.example.yaml` (`globalTTL`, `ttl`, `unloadTimeout` comments).

## 3. Concurrent models (groups vs matrix router)

Config section: `routing.router.use: group | matrix` (default `group`).
Legacy top-level `groups:`/`matrix:` keys still parse (back-compat, normalized
into `routing`); new configs should use `routing.router.settings.*`.

Group engine (`routing.router.settings.groups.<name>`):

| Field | Default | Meaning |
|---|---|---|
| `swap` | `true` | `true` = one member at a time (hot-swap); `false` = all members co-resident |
| `exclusive` | `true` | `true` = loading a member unloads all other groups; `false` = leaves others alone |
| `persistent` | `false` | `true` = this group is never unloaded by other exclusive groups |
| `members` | required | Model IDs (one group per model) |

- Default (no `routing` section): single implicit group, `swap: true,
  exclusive: true` = exactly one model resident — correct for 2× 27B on 32GB.
- Co-resident example: both 27B in one `swap: false, exclusive: true` group —
  only viable with heavy quant/context cuts; expect OOM (see §5).
- Matrix engine (`routing.router.settings.matrix`): `vars`, `evict_costs`,
  `sets` DSL (`&`, `|`, `()`, `+ref`). Solver evicts lowest-cost set to make
  room. Overkill for 2 models; consider only if a TTS/reranker joins later.
- Scheduler: `routing.scheduler.use: fifo` (only value) +
  `settings.fifo.priority: {<model>: <int>}` — higher priority jumps the
  queue. Proposed `unloadDelay`/debounce (PR #611) is NOT merged as of writing.
- Sources: `docs/config.example.yaml` (`routing` section);
  https://github.com/mostlygeek/llama-swap/issues/107 (groups design);
  https://github.com/mostlygeek/llama-swap/pull/611 (priority proposal).

## 4. Hot-swap API (stable)

Base = llama-swap listen address (default `:8080`). OpenAI endpoints trigger
swaps implicitly via `"model"` field — this IS the hot-swap path opencode
should use (backend-follows-picker, no extra calls).

| Method + path | Effect |
|---|---|
| `GET /v1/models` | List IDs/aliases; `?model=` filters props (autoload param ignored) |
| `GET /running` | Currently running models (#61) |
| `POST /api/models/unload` | Unload ALL models (#58) |
| `POST /api/models/unload/:model` | Unload one model (alias-aware) |
| `GET /api/profiles` / `PUT /api/profiles/active` | Runtime model-ID remap switch |
| `GET /upstream/:model<path>` | Direct passthrough to one upstream |
| `GET /health` | `OK` (proxy liveness, not model readiness) |
| `GET /metrics` | Prometheus system/GPU metrics |
| `GET /logs`, `GET /logs/stream[/proxy\|/upstream\|/:model]` | Buffered + live logs |
| `GET /ui` | Web UI (manual load/unload buttons) |

- No stable single-model LOAD endpoint: warm via any real inference request
  or `/upstream/:model` passthrough. `POST /api/models/load/:model` and
  `GET /api/ps`, `GET /api/models/:model` exist only in unmerged PR #755 —
  do NOT depend on them.
- In-flight swap semantics (`proxy/processgroup.go`): swap waits for
  fast-path in-flight requests (`inflight.Wait()`), stops previous process,
  proxies new model. Concurrent requests for different models in one
  `swap: true` group serialize; simultaneous multi-model bursts had a race
  fixed in #277 — keep `healthCheckTimeout` generous.
- Sources: README "llama-swap API" section; `proxy/proxymanager_api.go`
  (`addApiHandlers`); `proxy/processgroup.go` (`ProxyRequest`);
  https://github.com/mostlygeek/llama-swap/pull/755 (unmerged);
  https://github.com/mostlygeek/llama-swap/issues/58.

## 5. VRAM-full behavior + CPU/RAM offload

- llama-swap has NO VRAM sensor and no automatic OOM eviction. Conflict rule
  is explicit: "users are responsible for resolving configuration conflicts"
  (issue #107). If two models exceed VRAM, the second `cmd` simply fails
  (llama-server CUDA malloc error) while the first keeps serving.
- Queue, don't parallelize: per-model `concurrencyLimit` (default internal
  10; `0` = default) and `globalConcurrencyLimit` (default `0` = unlimited).
  Over-limit requests get HTTP `429`, never queued server-side. FIFO
  scheduler + priorities order swap contention.
- CPU/RAM offload is NOT a llama-swap feature — it is llama-server CLI flags
  inside each model's `cmd`: `--gpu-layers N`, `--ctx-size N`,
  `--cache-type-k/v`, `--mlock`, `--flash-attn`. Map preference "quant drop
  before ctx drop before offload" translates to: pick smaller quant in `cmd`
  → lower `--ctx-size` → lower `--gpu-layers` (spill to 64GB RAM). llama-swap
  only launches the command; it never rewrites these flags (except
  `filters.stripParams/setParams/setParamsByID`, which edit request JSON,
  not backend flags).
- Env/port plumbing: `${PORT}` auto-assigns from `startPort` (default 5800);
  `${MODEL_ID}`, `${PID}`, `macros`, per-model `env:` (e.g.
  `CUDA_VISIBLE_DEVICES`), `cmdStop` (e.g. `docker stop ${MODEL_ID}`).
- RTX 5090 32GB implication: with `swap: true, exclusive: true` (one
  resident), VRAM-full is a config error, not a runtime state — router ticket
  #30 should treat "second model requested" as evict-then-load with user-
  visible swap latency, not as concurrent residency. Concurrency belongs in a
  later ticket with measured numbers from #29.
- Sources: `docs/config.example.yaml` (`concurrencyLimit`,
  `globalConcurrencyLimit`, `filters`, `macros`, `env`, `cmdStop`);
  https://github.com/mostlygeek/llama-swap/issues/107;
  https://github.com/mostlygeek/llama-swap/discussions/659 (concurrent-forwarding limit).

## 6. Minimal config pointer for tickets #30/#31

Do not paste full dumps (per ticket scope). Canonical reference is
`docs/config.example.yaml` above. Decision inputs:

- One-resident default: omit `routing` OR declare one group
  `swap: true, exclusive: true` with both model IDs as members.
- TTL keys: `globalTTL`, `models.<id>.ttl`, `unloadTimeout`.
- Swap trigger: `"model"` request field; management: `POST
  /api/models/unload[/:model]`, `GET /running`, `GET /v1/models`.
- Offload knobs live in `models.<id>.cmd` (llama-server flags), not in
  llama-swap keys.

## 7. Limits / open questions for follow-ups

- Swap latency on 27B GGUF at 120-200k ctx is unmeasured — needs #29 before
  #30 sets TTL/thresholds.
- No debounce/`unloadDelay` in stable (PR #611 open) — agentic burst traffic
  may thrash; mitigation today is TTL + FIFO `priority`, not a timer.
- No per-model VRAM accounting — #28 must compute ctx feasibility offline.
- Matrix router + `profiles`/`selectors` add power but also config surface;
  defer unless the 2-model group design proves insufficient.
