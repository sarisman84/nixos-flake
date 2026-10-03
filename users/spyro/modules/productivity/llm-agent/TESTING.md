# llm-agent Testing Instructions

## Prerequisites

After editing `default.nix` or `models.json`, deploy with:

```bash
config build two-b
```

(or `sudo nixos-rebuild switch --flake .#two-b --show-trace`)

Generated files are baked into the Nix store — you must rebuild before testing.
Building is enough to test configuration; switching is needed to test services.

## The backend is always on

The `llama-swap` backend is a systemd user service (ADR 0001). It starts at login
and stays up whether or not opencode is running. Nothing starts it on demand.

```bash
systemctl --user status llama-swap          # is it up?
systemctl --user restart llama-swap         # reload generated config
journalctl --user -u llama-swap -n 50       # recent log
```

Verify it is reachable:

```bash
curl -s http://127.0.0.1:8080/health
curl -s http://127.0.0.1:8080/running       # what is resident right now
```

A pre-existing manually-started `llama-swap` will hold port 8080 and make the
unit fail its preflight check. Kill it first:

```bash
pkill -f '(^|/)llama-swap( |$)'
```

`/health` always returns OK — it does not tell you whether a model is loaded.
Use `/running` for that.

## Selecting models

There is no wrapper. `opencode` is the raw binary, so `--model`, `--cloud` and
`opencode models` no longer exist.

```bash
opencode                                        # registry default
opencode --model llama.cpp/gpt-oss-20b          # local model
opencode --model llama.cpp/gpt-oss-20b run "hi" # local, one-shot
opencode --model opencode/big-pickle            # cloud model
```

Local model keys are the keys under `llama.cpp` in `models.json`; cloud keys are
under `opencode`. The key is the identity sent on the wire — it must match the
model ID in the generated swap config.

Switching models in the TUI picker hot-swaps the resident model. You do not need
to restart opencode or the backend.

## Verifying a swap

```bash
# before
curl -s http://127.0.0.1:8080/running
nvidia-smi --query-gpu=memory.used --format=csv
# ... send a message in opencode with a different model selected ...
# after
curl -s http://127.0.0.1:8080/running
nvidia-smi --query-gpu=memory.used --format=csv
```

Exactly one model is resident at a time — that is the `swap: true` /
`exclusive: true` swap group in the generated config, and `nix flake check`
asserts it.

## Verifying registry validation

```bash
nix flake check          # malformed models.json fails here, with a message
```

Registry mistakes surface at build time, never at inference time.

## API keys

Keys live in `env/*.env` (gitignored) and are rendered at activation time into
`~/.config/environment.d/50-llm-agent.conf` so both front-ends get them:

```bash
ls -l ~/.config/environment.d/50-llm-agent.conf   # 600, not in the store
systemctl --user show-environment | grep FIGMA    # picked up by the user manager
```

They are deliberately not `home.sessionVariables` — that would bake the keys
into the Nix store. To pick up a changed key, restart the user manager or log
back in.

## Quick sanity matrix

| Check | Command | Expect |
|---|---|---|
| Evaluation | `nix flake check` | passes |
| Build | `sudo nixos-rebuild build --flake .#two-b` | succeeds |
| Service defined | `systemctl --user status llama-swap` | active (after switch) |
| Backend reachable | `curl -s http://127.0.0.1:8080/health` | OK |
| Local model loads | pick a local model, send a message | reply |
| Hot swap | switch model mid-session | reply, `/running` shows the new one |
| Cloud model | pick a cloud model, send a message | reply, no local load |
| Desktop app | pick a local model in the desktop app | reply |
| Keys loaded | `systemctl --user show-environment \| grep FIGMA` | present |

## Not yet implemented

The unload policy described in ADR 0002 (plugin-owned idle unload, leases,
heartbeat, failsafe floor) is **not built yet**. Until it is, `globalTTL` is `0`
and a model stays resident indefinitely once loaded — stop it by hand with
`curl -X POST http://127.0.0.1:8080/unload`.

Note that `POST /api/models/unload` does **not** protect in-flight requests: it
terminates a server mid-request. Only do this when nothing is generating.