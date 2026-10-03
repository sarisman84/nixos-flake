# llm-agent workflow

How a prompt becomes tokens on this machine, and how to change the setup. Vocabulary is in [`CONTEXT.md`](../../CONTEXT.md); registry fields in [`registry.md`](./registry.md); test commands in [`TESTING.md`](../../users/spyro/modules/productivity/llm-agent/TESTING.md).

## Request path

```text
opencode (CLI or desktop)
  → provider "llama.cpp", baseURL http://127.0.0.1:8080/v1
  → llama-swap router
  → the one resident llama-server → GPU
```

`llama-swap` fronts every **model entry** but holds at most one **resident model**: the `local-llms` **swap group** sets `swap = true, exclusive = true`, so requesting a different member evicts the current one (full unload + reload, ~4 s cold). Cloud entries (`opencode` provider) never touch the backend.

## Service lifecycle

`llama-swap` is a systemd user service, started at login via `default.target` and always on (see [`0001-always-on-llama-swap-backend.md`](../adr/0001-always-on-llama-swap-backend.md)). The proxy costs ~10 MB; the resident model is the resource, managed separately.

```bash
systemctl --user status llama-swap     # is it up?
journalctl --user -u llama-swap -n 50  # what did it do?
systemctl --user restart llama-swap    # pick up a rebuilt config
curl -s http://127.0.0.1:8080/health  # always OK; says nothing about models
curl -s http://127.0.0.1:8080/running # what is resident right now
```

An `ExecStartPre` preflight fails the unit instead of crash-looping when a stray `llama-swap` already holds `:8080` — kill it with `pkill -f '(^|/)llama-swap( |$)'`.

Rebuild alone never reaches the running process. After changing anything the backend reads (`config.yaml`), restart the service; the new file only takes effect on next start.

## Configuration flow

`models.json` is the single source of truth. `default.nix` derives everything else, and `nix flake check` asserts both the registry shape and the generated artefacts:

| Edit this | It generates | Read by |
|---|---|---|
| `llama.cpp` entries | `opencode.json` provider block | opencode model picker |
| `default` | `opencode.json` session default | new sessions |
| `llama.cpp` entries | `config.yaml` models + swap group | `llama-swap` at (re)start |
| `unloadPolicy` | `~/.config/llama-swap/unload-policy.json` | the unload plugin |
| `policy/*.ts` | `plugins/llm-agent-unload.ts` (single spliced file) | opencode at startup |

Retuning is an edit to `models.json`, then the 3-tier workflow (`nix flake check` → build → `config build two-b`) plus a service restart when the backend is affected.

## Unload policy lifecycle

Each opencode process loads the plugin (singleton-guarded; the factory runs more than once per process), writes a heartbeat, and publishes a **lease** under `$XDG_STATE_HOME/llm-agent/`. When every live lease has been **idle** past `idleThresholdSeconds` (300 s) and the **settle delay** (15 s) has elapsed with no activity, the plugin sends `POST /api/models/unload` and VRAM returns to baseline. Backend-side `ttl` stays `0`; the plugin owns the decision (see [`0002-plugin-owned-unload-policy.md`](../adr/0002-plugin-owned-unload-policy.md)).

```bash
cat ~/.config/llama-swap/unload-policy.json   # thresholds in force
state="${XDG_STATE_HOME:-$HOME/.local/state}/llm-agent"
cat "$state/heartbeat.json"                    # missing = plugin not loaded
```

**A missing heartbeat means the plugin failed to load** — opencode discards plugin load failures silently. If it is ever missing again, check what the deployed file imports before suspecting the policy logic.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Internal Server Error` on a local model | upstream `llama-server` died at startup; journal shows `upstream command exited prematurely` | run the generated `llama-server` command by hand — `llama-swap` discards its stderr, which holds the real error (usually VRAM, see `nvidia-smi`) |
| Heartbeat missing | plugin failed to load | inspect the deployed file's imports; only `node:` builtins may appear |
| Unit fails preflight | stray backend holds the port | `pkill -f '(^|/)llama-swap( |$)'`, then restart |
| Changed `models.json`, nothing different | running process still has the old file | `systemctl --user restart llama-swap` |
| API keys missing in desktop app | user manager predates the key | re-activate or restart the user manager (`env/*.env` → `environment.d/50-llm-agent.conf`, never the store) |
