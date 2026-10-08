# Closing the resident `llama-server` on opencode exit and host sleep

Scope: can the resident `llama-server` be closed (a) when **opencode exits** and (b) when the
**host suspends/sleeps**? Every load-bearing claim cites a primary source (official docs or
source code). **Verified** = read in source; **Inferred** = reasoned from verified facts.

## Background

- Stack: `opencode` → `llama-swap` (`http://127.0.0.1:8080`) → one resident `llama-server`.
- `llama-swap` is an always-on systemd **user** service (ADR 0001).
- The backend never auto-unloads: every model ships `ttl: 0` (`models/*.json`) and
  `globalTTL = 0` (`default.nix:439`). The plugin owns the unload decision (ADR 0002).
- The only way to release the resident model is `POST http://127.0.0.1:8080/api/models/unload`.

## The unload mechanism (shared by both triggers)

### llama-swap: `POST /api/models/unload`

- Route registration: `POST /api/models/unload` → `handleAPIUnloadAll`,
  `POST /api/models/unload/{model...}` → `handleAPIUnloadModel`, `GET /unload` → `handleUnload`
  (`internal/server/server.go`, `routes()`).
- `handleUnload` calls `s.local.Unload(0)` (`internal/server/api.go`).
- `Unload` targets all running models; `timeout <= 0` falls back to each model's
  `unloadTimeout` (`internal/router/base.go`).
- `sendUnload` blocks on `<-req.respond`, so the caller waits for the stop to finish
  (`internal/router/base.go`).
- `OnUnload` calls `s.effects.StopProcesses(timeout, targets)` **synchronously** and does **not**
  check in-flight requests, so an explicit unload kills in-flight streams
  (`internal/router/scheduler/fifo.go`, `OnUnload`). This confirms ADR 0002's "kills in-flight".
- `StopProcesses` runs `p.Stop(timeout)` per process in parallel and `wg.Wait()`s
  (`internal/router/base.go`).
- `killProcess` sends **SIGTERM** to the process group, waits up to `unloadTimeout`, then
  **SIGKILL**, then waits for exit (`internal/process/process_command.go`).
- **Synchronous**: the HTTP handler blocks until the `llama-server` child is stopped and VRAM is
  freed. `unloadTimeout` is not set in the flake's generated config, so llama-swap's default
  (10 s, per `docs/kb/guides/model-runtime/ttl-and-unloading.md`) applies.

### llama-server: graceful shutdown on SIGTERM

- `sigaction(SIGTERM, &sigint_action)` (`tools/server/server.cpp:515`).
- `signal_handler` → `shutdown_handler` → `ctx_server.terminate()` (`server.cpp:28-37`, `500-504`).
- The main thread blocks on `ctx_server.start_loop()`; `terminate()` unblocks it
  (`server.cpp:555`).
- After the loop returns, `clean_up()` runs `llama_backend_free()`, which releases the GPU backend
  and therefore the VRAM (`server.cpp:464-472`, `557`).
- There is **no HTTP shutdown endpoint**; a signal is the only mechanism.
- A second SIGINT/SIGTERM forces an immediate `exit(1)` (`server.cpp:28-37`).
- **Inferred** timing: stop HTTP + terminate context + `llama_backend_free()` ≈ 1–3 s, well within
  the 10 s `unloadTimeout`.

## Trigger A — opencode exits

### Verified: the `dispose` hook runs on exit

- The plugin `Hooks` type includes `dispose?: () => Promise<void>`
  (`packages/plugin/src/index.ts`, `anomalyco/opencode@dev`).
- The plugin loader registers a finalizer that calls each hook's `dispose`
  (`packages/opencode/src/plugin/index.ts`).
- TUI exit → worker `shutdown` → `await InstanceRuntime.disposeAllInstances()` →
  `InstanceStore.disposeAll()` → instance disposal → plugin `dispose`
  (`packages/opencode/src/cli/tui/worker.ts`, `project/instance-runtime.ts`,
  `project/instance-store.ts`).
- The whole shutdown is bounded by a 5 s timeout: `withTimeout(client.call("shutdown"), 5000)`
  then `worker.terminate()` (`packages/opencode/src/cli/cmd/tui.ts`). `withTimeout` is a
  `Promise.race` and does **not** cancel the underlying work (`packages/opencode/src/util/timeout.ts`).

### The current `dispose` hook does not unload

- `dispose` (`policy/plugin.ts:445`) only clears the timer and removes the lease. It does **not**
  call the existing `unload()` (`policy/plugin.ts:322`), which already issues the
  `POST /api/models/unload` fetch.

### Timing analysis

- The `dispose` hook's `fetch(POST /api/models/unload)` sends the request immediately.
- llama-swap sends SIGTERM to `llama-server` within milliseconds of receiving it.
- `llama-server` frees VRAM in ~1–3 s (**Inferred**).
- The worker is terminated at 5 s, so the fetch's *response* is likely cut off — but the SIGTERM was
  already sent and the VRAM is already freed. The unload only needs the request to be *sent*, not
  acknowledged.

### Verdict A

**Yes.** Adding `await unload()` to the `dispose` hook closes the resident model on opencode exit.
The 5 s worker timeout cuts off the HTTP response but not the unload, because llama-swap sends
SIGTERM immediately and `llama-server` frees VRAM in ~1–3 s.

## Trigger B — host suspends / sleeps

### Verified: logind emits `PrepareForSleep`

- `PrepareForSleep(b start)` is sent "right before (with the argument `true`) or after (with the
  argument `false`) the system goes down for ... suspend/hibernate"
  (`systemd/systemd@main`, `man/org.freedesktop.login1.xml:786-799`).
- It is explicitly for applications to "save data on disk, release memory, or do other jobs that
  should be done shortly before shutdown/sleep, in conjunction with delay inhibitor locks."

### Verified: delay inhibitor locks give lead time

- A `delay` lock on `sleep` delays the suspend until the lock is released or `InhibitDelayMaxSec`
  elapses (`https://systemd.io/INHIBITOR_LOCKS`).
- Default `InhibitDelayMaxUSec = 5000000` (5 s) (logind `Manager` introspection, same page).
- **Warning**: "watching `PrepareForSleep(true)` without taking a delay lock is racy and should not
  be done" (`https://systemd.io/INHIBITOR_LOCKS`).

### The pattern

1. Take a `delay` lock on `sleep` at service start.
2. On `PrepareForSleep(true)`: call `POST /api/models/unload`, then release the lock.
3. On `PrepareForSleep(false)` (after wake): re-take the delay lock.

### Caveats

- Only for logind-mediated (high-level, user-induced) suspend cycles, not low-level kernel-induced
  ones (`https://systemd.io/INHIBITOR_LOCKS`).
- Taking inhibitor locks is polkit-gated; delay locks are the easiest to obtain
  (`https://systemd.io/INHIBITOR_LOCKS`).
- A user-level systemd service can take the lock and listen on the system bus.

### Verdict B

**Yes.** A user-level systemd service that holds a `sleep` delay lock and listens for
`PrepareForSleep(true)` can close the resident model before the host suspends, with up to
`InhibitDelayMaxSec` (default 5 s) of lead time.

## What would change in this flake

1. **opencode exit** — one-line change to the `dispose` hook in `policy/plugin.ts`: add
   `await unload()` after removing the lease. `unload()` already exists (`policy/plugin.ts:322`).
2. **host sleep** — a new user-level systemd service (e.g. `llama-swap-sleep-guard.service`) that:
   - takes a `sleep` delay lock at start;
   - listens for `PrepareForSleep(true)` / `(false)` on the system bus;
   - on `true`: `curl -X POST http://127.0.0.1:8080/api/models/unload`, then releases the lock;
   - on `false`: re-takes the lock.
   - wired in `default.nix` alongside the existing `llama-swap` user service.
3. **Config** — no change to the unload path (`ttl: 0`, `globalTTL = 0` stay; the plugin and the new
   service call the same endpoint). Optionally raise `InhibitDelayMaxSec` in `logind.conf` if the
   unload ever approaches 5 s (it should not; ~1–3 s).

## Open questions

- Whether a frozen-then-resumed `llama-server` is in a clean state. If not, unloading before sleep
  is more than a nicety. Not verified here.
- Exact `unloadTimeout` default (10 s per llama-swap docs; not set in the flake's generated config).
- The polkit rule an unprivileged user service needs to take a `sleep` delay lock
  (`org.freedesktop.login1.inhibit-delay-sleep`).

## Sources

opencode (`github.com/anomalyco/opencode`, `dev`):

- `packages/plugin/src/index.ts` — `Hooks` type, `dispose` hook.
- `packages/opencode/src/plugin/index.ts` — plugin loader, `dispose` finalizer.
- `packages/opencode/src/cli/cmd/tui.ts` — TUI shutdown, 5 s timeout, `worker.terminate()`.
- `packages/opencode/src/cli/tui/worker.ts` — worker `shutdown`, `disposeAllInstances()`.
- `packages/opencode/src/project/instance-runtime.ts` — `disposeAllInstances()`.
- `packages/opencode/src/project/instance-store.ts` — `disposeAll()`.
- `packages/opencode/src/effect/instance-registry.ts` — `disposeInstance()`.
- `packages/opencode/src/effect/instance-state.ts` — instance disposer.
- `packages/opencode/src/util/timeout.ts` — `withTimeout` is a `Promise.race`.

llama-swap (`github.com/mostlygeek/llama-swap`, `main`):

- `internal/server/server.go` — route registration.
- `internal/server/api.go` — `handleUnload` → `Unload(0)`.
- `internal/router/base.go` — `Unload`, `sendUnload`, `StopProcesses`.
- `internal/router/scheduler/fifo.go` — `OnUnload` (synchronous, no in-flight check).
- `internal/process/process_command.go` — `killProcess` (SIGTERM → SIGKILL).
- `docs/kb/guides/model-runtime/ttl-and-unloading.md` — `unloadTimeout` default (10 s).

llama.cpp (`github.com/ggml-org/llama.cpp`, `master`):

- `tools/server/server.cpp` — signal handling, `clean_up()`, `llama_backend_free()`.

systemd (`github.com/systemd/systemd`, `main`) and systemd.io:

- `man/org.freedesktop.login1.xml` — `PrepareForSleep` signal.
- `https://systemd.io/INHIBITOR_LOCKS` — delay locks, `InhibitDelayMaxSec`, racy-signal warning.
