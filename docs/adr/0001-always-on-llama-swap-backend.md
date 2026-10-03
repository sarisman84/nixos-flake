# Always-on llama-swap backend

Previously the `opencode` wrapper started `llama-swap` lazily and stopped it when the last opencode process exited, with a systemd timer as a backstop. The backend is now a long-lived systemd user service started at login, and only the **resident model** is de-allocated.

## Considered options

- **Demand-start (rejected).** `opencode-desktop` forks a bundled sidecar and never executes anything from `PATH`, so it can never trigger the wrapper. Selecting a local model in the desktop app only worked if a CLI session had already started a backend. Always-on removes that whole bug class.
- **Socket activation (rejected).** Solves the same problem with more moving parts and no benefit — llama-swap's own listener is the socket.

## Consequences

- The wrapper's start, health-check, and on-exit teardown logic is obsolete (see `0002-plugin-owned-unload-policy.md` for what replaces it).
- The proxy costs ~10 MB and one listening socket. The resource that matters is the resident model, which is now managed separately.
- `/health` is always reachable, so it can no longer be used to infer whether the backend was just started.
