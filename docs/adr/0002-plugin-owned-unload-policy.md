# Plugin-owned unload policy over llama-swap's native TTL

llama-swap can unload an idle **resident model** itself via per-model `ttl` / `globalTTL`. We deliberately do not use it as the primary mechanism. A systemd user service owns the backend (see `0001-always-on-llama-swap-backend.md`), and an opencode plugin owns when the resident model is unloaded. `globalTTL` is set to 1800 s as a failsafe floor only.

> **Status: decided, not implemented.** The plugin, the leases and the heartbeat do not exist yet; `globalTTL` is still `0` and unload is manual. Tracked in #49–#53. This ADR records the decision so the floor is not later mistaken for an oversight.

## Considered options

- **llama-swap `ttl` as the primary mechanism (rejected).** It measures *HTTP* inactivity against the backend. An opencode session sitting idle with a local model selected — you are reading the output — still looks idle to it, so the model is unloaded while you are mid-conversation. It also has no notion of "a cloud model is selected", which is a state only opencode knows about.
- **A systemd service parsing opencode's internals (rejected).** No silent-failure mode, but it means reaching into opencode's session store or log format from outside. A documented plugin hook is the better coupling.
- **Trusting the backend's in-flight protection (rejected).** It does not exist on the explicit-unload path — see Consequences.

## Consequences

- **`POST /api/models/unload` kills in-flight requests.** `conflictsWithInFlight` is called only from the swap path (`fifo.go:131`, `fifo.go:432`); `OnUnload` deliberately bypasses it (`fifo.go:258-262`, documented at `base.go:387-390`). An in-flight generation gets a truncated stream. The plugin must therefore establish idleness from opencode's `session.status` *and* the backend's inflight SSE stream before unloading — llama-swap exposes live inflight only via `GET /api/events`, never as a plain GET.
- **The policy can fail silently.** opencode wraps plugin loading in `Effect.ignoreCause` (`external.ts:87`), so an import or shape failure produces no log at any level. The plugin writes a heartbeat on load and a timer asserts it is fresh, turning a silent no-op into a visible failure.
- **`event` hooks are directory-filtered** (`plugin/index.ts:255`, no global exemption), so one plugin instance cannot observe other working directories' sessions. `chat.params` uses a separate dispatch path with no such filter and fires for every provider including cloud — it is the reliable place to observe model selection.
- **N instances share one backend**, so unload is global while idleness is per-instance. Instances publish leases and only unload when every lease is idle.
