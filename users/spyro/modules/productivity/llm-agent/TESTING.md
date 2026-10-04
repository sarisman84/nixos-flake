# llm-agent Testing Instructions

## Prerequisites

After editing `default.nix` or the registry (`config.json`, `models/*.json`), deploy with:

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

Local model keys are the `models/<key>.json` file names (the keys listed in
`config.json`); cloud keys are under `cloud-models.json`. The key is the identity
sent on the wire — it must match the model ID in the generated swap config.

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
nix flake check          # a malformed registry file fails here, with a message
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

## The unload policy

A session going idle past the threshold unloads the resident model. The policy is
an opencode plugin; the thresholds live in `config.json` under `unloadPolicy` and
reach the plugin through the generated `~/.config/llama-swap/unload-policy.json`.

```bash
cat ~/.config/llama-swap/unload-policy.json      # thresholds actually in force
state="${XDG_STATE_HOME:-$HOME/.local/state}/llm-agent"
cat "$state/heartbeat.json"                      # written when the plugin loads
ls   "$state/leases/"                            # one lease per live instance
```

The heartbeat matters because opencode discards the cause of a plugin load
failure: a plugin that throws on import produces no log at any level. **A missing
or stale heartbeat means the policy is not running**, which is otherwise
indistinguishable from "nothing needed unloading".

It has already caught a real one. The plugin was first deployed as an entry file
re-exporting `../llm-agent/plugin.js`, but Home Manager compiles each `home.file`
to its own store path named after the target — so that relative import resolved
against `/nix/store`, the load failed, and nothing anywhere said so. The plugin
now ships as a single self-contained file. **If the heartbeat is ever missing
again, check what the deployed file actually imports before suspecting the
policy logic.**

### Watching a decision

`client.app.log` entries carry the reason. To see them:

```bash
opencode --print-logs --log-level DEBUG 2>&1 | grep "unload decision"
```

Reasons, all of which mean *do not unload* unless stated:

| Reason | Meaning |
|---|---|
| `all-leases-idle` | every live lease is past the threshold — **this one unloads** |
| `lease-busy` | some instance is mid-generation |
| `lease-active` | some instance did local work within the threshold |
| `lease-settling` | an idle observation is younger than the settle delay |
| `lease-unobserved` | an instance started within the settle delay and has seen no session |
| `no-live-lease` | the lease set was readable but nothing in it belongs to a live process |
| `inflight-present` | the backend reported a request in flight |
| `lease-set-unreadable` | the lease set could not be read — never reads as permission |

### Verifying an unload

```bash
curl -s http://127.0.0.1:8080/running     # {"running":[...]} before
nvidia-smi --query-gpu=memory.used --format=csv
# ... start a local session, then stop prompting and wait out the threshold ...
curl -s http://127.0.0.1:8080/running     # {"running":[]} after
```

`POST /api/models/unload` does **not** consult the backend's in-flight tracking —
that guard exists only on the swap path. Unload terminates a server mid-request
and the client sees a truncated stream. Until #50 lands, in-flight state is
self-reported from the plugin's own sessions, so **do not unload by hand while
another instance is generating**.

### Unit tests

The decision function is pure and runs without a GPU, a backend or a running
opencode:

```bash
nix develop .
bun test users/spyro/modules/productivity/llm-agent/policy
cd users/spyro/modules/productivity/llm-agent/policy && tsc --noEmit -p tsconfig.json
```

## Not yet implemented

- **#50** — the backend's in-flight stream as the authority on whether a request
  is running. Until then the plugin only knows about its *own* sessions, so an
  instance that does not carry the plugin is invisible to the policy.
- **#51** — a session that switches to a cloud model releases the resident model
  immediately instead of waiting out the threshold.
- **#52** — check-and-unload under a lock, so two idle instances cannot unload
  across each other.
- **#53** — the `globalTTL` failsafe floor, currently still `0`.

**Migrating warning.** Until every opencode instance is deployed with the plugin,
a plugin-bearing instance can unload a model that an older instance is actively
using, because the older one publishes no lease. Deploy before relying on this.