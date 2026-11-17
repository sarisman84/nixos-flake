# Plugin-owned unload policy over llama-swap's native TTL

llama-swap can unload an idle **resident model** itself via per-model `ttl` / `globalTTL`. We deliberately do not use it as the primary mechanism. A systemd user service owns the backend (see `0001-always-on-llama-swap-backend.md`), and an opencode plugin owns when the resident model is unloaded. `globalTTL` is set to 1800 s as a failsafe floor only.

> **Status: partly built (#49), ported to the opencode v2 plugin API (#96).** The plugin, the lease and the heartbeat exist, and a session going idle past the threshold does unload the resident model. The v2 port restores the plugin after opencode's upgrade to the v2 API — the v1 plugin no longer loads because the v2 loader requires a `default` export. Still to come: the failsafe floor (#53), the backend's in-flight stream as the authority (#50), cloud-selection release (#51), and cross-instance arbitration under a lock (#52). `globalTTL` is still `0`. This ADR records the whole decision so the floor is not later mistaken for an oversight.

## What #49 established

- **The seam.** `shouldUnload(leaseSet, inflight, now, policy) → { unload, reason }` in `policy/decision.ts`. It needs no GPU, no backend, no filesystem and no running opencode, which is the only reason the policy is testable at all.
- **The lease.** Every instance publishes `~/.local/state/llm-agent/leases/<pid>.<id>.json`: pid, boot id, `startedAt`, `lastLocalActivityAt`, `busySince`, `idleSince`. Liveness is resolved by the reader from pid *and* boot id, so a recycled pid or a lease from a previous boot cannot pin the model.
- **Unavailability refuses.** An unreadable lease set, an unreadable lease file, an unparseable lease, and a set with nothing alive in it all yield `unload: false`.
- **Host facts, each established against opencode 2.2.6 (source at the pinned tag plus a live `opencode run` probe) rather than read off a changelog**, and recorded in `policy/plugin.ts`:
  1. The plugin is a default export `{ id, setup }`, and `setup` runs **once per open project (location)** in a process, not once per process. The policy state (leases, timer, heartbeat) is a per-process singleton that each location's `setup` contributes to; the full teardown is deferred to the last location leaving. Without the singleton one process would publish one lease per open project and run one unload timer per project.
  2. Model selection is read from `ctx.session.hook("context", …)`, which carries `{ sessionID, model: { id, providerID } }` — the `chat.params` replacement. There is no `chat.message`/`chat.params` in v2.
  3. `session.status` reports `busy` / `idle` / `retry`; events arrive as `{ type, data }` (payload under `data`, not `properties`); streaming activity arrives as `session.text.delta` (the `message.part.delta` replacement).
- **The settle delay is load-bearing, not decorative.** Observed live: a decision of `lease-settling` preceded the `all-leases-idle` that unloaded.
- **One idle epoch, one unload attempt.** A turn that fails or is cancelled can report idle repeatedly; the idle clock only advances on the busy-to-idle *edge*.

## Consequences of what #49 left out

- **In-flight state is still self-reported.** #49 derives in-flight entries from its own sessions, because the backend's authoritative stream is #50. Its wire format, probed against llama-swap 249 so #50 does not have to rediscover it:

  ```
  GET /api/events                       # SSE, `event:message`, then data:
  data:{"type":"inflight","data":"{\"operation\":\"snapshot\"}"}
  data:{"type":"inflight","data":"{\"operation\":\"upsert\",\"request\":{\"id\":\"7\",\"model\":\"...\",\"req_path\":\"/v1/chat/completions\",...}}"}
  data:{"type":"inflight","data":"{\"operation\":\"remove\",\"id\":\"7\"}"}
  ```

  Three things to know: `data` is a **nested JSON string** and must be parsed
  twice; the operation is `remove`, not `delete`; and each entry names its
  `model`, which is what makes per-model refusal possible. A `snapshot` with no
  `request` is the initial state, not an empty one to be ignored.

- **The deployed plugin is one spliced file.** `home.file.<name>.text` compiles
  each file to its own store path named after the target with separators
  stripped, so the entry's `../llm-agent/plugin.js` resolved against the Nix
  store and the plugin silently never loaded. It now ships as a single
  self-contained file, with `nix flake check` asserting the splice stayed
  sound. A sibling instance's request is covered by its lease being busy, but a request from an instance that does *not* carry the plugin is invisible. Until every instance is deployed, an unload can truncate such a request — this is the concrete reason #50 must land before the policy is trusted in anger.
- **Auxiliary traffic still refreshes the lease.** `chat.params` fires for session-title generation, which today runs on a local model (#54). Every session start therefore refreshes `lastLocalActivityAt` once. That is the conservative direction — it holds the model longer rather than unloading during work — and #54 removes the cause.

## Considered options

- **llama-swap `ttl` as the primary mechanism (rejected).** It measures *HTTP* inactivity against the backend. An opencode session sitting idle with a local model selected — you are reading the output — still looks idle to it, so the model is unloaded while you are mid-conversation. It also has no notion of "a cloud model is selected", which is a state only opencode knows about.
- **A systemd service parsing opencode's internals (rejected).** No silent-failure mode, but it means reaching into opencode's session store or log format from outside. A documented plugin hook is the better coupling.
- **Trusting the backend's in-flight protection (rejected).** It does not exist on the explicit-unload path — see Consequences.

## Consequences

- **`POST /api/models/unload` kills in-flight requests.** `conflictsWithInFlight` is called only from the swap path (`fifo.go:131`, `fifo.go:432`); `OnUnload` deliberately bypasses it (`fifo.go:258-262`, documented at `base.go:387-390`). An in-flight generation gets a truncated stream. The plugin must therefore establish idleness from opencode's `session.status` *and* the backend's inflight SSE stream before unloading — llama-swap exposes live inflight only via `GET /api/events`, never as a plain GET.
- **The policy can fail to load.** v2 logs a plugin load failure as a `failed to load plugin` WARN in `~/.local/share/opencode/log/opencode.log` (the v1 `Effect.ignoreCause` silence is gone), but a plugin that loads and then never heartbeats is still a silent no-op. The plugin writes a heartbeat on load and a timer asserts it is fresh, turning either failure into a visible one.
- **The event stream is location-scoped** (the plugin host runs with an ambient Location, and the bus restricts delivery to that Location plus global events), so one plugin instance cannot observe other projects' sessions. The `context` hook fires for every provider including cloud — it is the reliable place to observe model selection.
- **N instances share one backend**, so unload is global while idleness is per-instance. Instances publish leases and only unload when every lease is idle.
