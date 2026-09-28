# PROTOTYPE SKETCH — throwaway, not production. Do not import from real modules.

## Question it answers

How do `opencode --model <name>` / `--cloud <name>` / bare-default behave
once `llama-swap` owns the server? (Ticket: Prototype opencode wiring and
hot-swap UX.)

## Files

- `config.yaml.SKETCH` — what Nix would generate for the swap proxy: one
  entry per model entry, decided flags baked in
  (`--ctx-size 32768 --cache-type-k q8_0`, `ttl: 120`).
- `llama-swap.service.SKETCH` — persistent systemd user unit shape
  (`-watch-config` so rebuilds apply without manual restarts).
- `opencode-wrapper.SKETCH.sh` — slimmed wrapper: arg parsing + registry
  validation + exec. No spawn, no health loop, no trap-kill.
- `demo.SKETCH.sh` — runnable cases (bash only, inline fixture registry).

## Run it

```bash
bash users/spyro/modules/productivity/llm-agent/prototype-hot-swap/demo.SKETCH.sh
```

## Proposals baked in — react to THESE

1. **Proxy down → fail fast (exit 3), no silent cloud fallback.** Rationale:
   silently spending cloud budget (or leaking prompts off-machine) when the
   user asked for local is worse than an error with log pointers. Counter:
   fall back to the default cloud model with a loud warning?
2. **In-session switching via opencode's own model picker.** The proxy's
   `GET /v1/models` lists both keys, so opencode can switch upstream servers
   mid-session with no client restart. The wrapper only pins the *first*
   model. Is picker-driven switching acceptable as "hot-swap", or must
   `opencode --model` re-target a running session?
3. **`--cloud` bypasses the proxy entirely**, unchanged from today.
4. **Logs move** from `/tmp/opencode-llama-server.log` to
   `journalctl --user -u llama-swap` (proxy) — per-model upstream logs via
   the proxy's `/logs` endpoint. OK, or do you want a file tail like today?
5. **`models` subcommand** passes through to opencode untouched (it will
   query the proxy's `/v1/models`).

## DECIDED (user reaction, 2026-09-28)

- **Generated files live outside the repo, under the user dir.** Nothing
  generated in the repo: `opencode.json` → `~/.config/opencode/opencode.json`
  (already `home.file`-managed today), swap config →
  `~/.config/llama-swap/config.yaml`, model registry →
  `~/.config/llama-swap/models.json` (wrapper runtime reads). Repo holds
  only Nix declarations. Implementer validates the `home.file` mechanics.
- Rest of the sketch accepted as-is (fail-fast on proxy-down, picker-driven
  in-session switching, `--cloud` bypass, journald logs, `models`
  passthrough).

## Deliberately NOT in the sketch

- Real Nix generation, real `home.file` paths, stable-vs-unstable package
  wiring, `maxCtxSize` opt-in plumbing, HF cache prefetch, soak numbers.
  Those are implementation detail for after the route is agreed.
