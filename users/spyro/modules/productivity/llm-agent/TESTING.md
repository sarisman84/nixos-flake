# llm-agent Testing Instructions

## Prerequisites

After editing `opencode-wrapper.sh`, deploy with:
```bash
just build two-b
```
(or `sudo nixos-rebuild switch --flake .#two-b --show-trace`)

The wrapper is baked into the nix store — you must rebuild before testing.

---

## Usage (enforced)

The wrapper requires the user to name the mode with a keyword:
`--model` for a local model, `--cloud` for a cloud model.
Both take a **bare model name** — the key in `models.json` — and the
provider prefix (`llama.cpp/`, `opencode/`) is re-attached internally.

```bash
opencode --model <name>    # local model (ensures swap backend)
opencode --cloud <name>    # cloud model (skips backend)
opencode                   # default model from models.json (interactive)
opencode [opencode args...]  # subcommands (models, run, mcp, ...)
```

- `--model` takes a name that must be a key under `llama.cpp` in
  `models.json`; the swap backend is ensured (started if missing) and the
  picked model loads on demand. Unknown names are rejected and the available
  models are listed.
- `--cloud` takes a name that must be a key under `opencode` in
  `models.json`; unknown names are rejected and the available models are listed.
- `--model` and `--cloud` are mutually exclusive.
- A **bare `opencode`** (no model flag) uses the **default model** set in
  `models.json` under the `default` key: `{"provider", "name"}` where provider
  is `llama.cpp` or `opencode`. The name must be registered under that provider.
  Currently set to local `qwen3-8b` (efficient, escalation via picker).
- Subcommands without a model flag (`models`, `mcp`, …) are allowed and do
  **not** touch the backend.
- Bare invocations *with* args (e.g. `opencode run "hi"`) also bypass the
  wrapper's default resolution and backend ensure — they rely on the generated
  `opencode.json` default model and an already-running backend.

Test commands:
```bash
# Default model (bare opencode; interactive session)
opencode

# Local models (must use --model; backend ensured, model loads on demand)
opencode --model qwen3-8b
opencode --model qwen3.8-27b
opencode --model qwen3.8-27b-200k

# Cloud model (must use --cloud)
opencode --cloud big-pickle

# Model + one-shot prompt
opencode --model qwen3-8b run "Say hello in 5 words"
opencode --cloud big-pickle run "Say hi"

# Subcommands (no model flag; no local server started)
opencode models
opencode run "hello"

# Rejected (should print usage/available models, exit 2):
opencode qwen3.8-27b                      # positional model, no --model
opencode --model not-a-real-model         # local model not in models.json
opencode --cloud not-a-real-model         # cloud model not in models.json
opencode --model big-pickle               # --model with a cloud-only name
opencode --cloud qwen3.8-27b              # --cloud with a local-only name
opencode --model a --cloud b              # both flags
opencode --model                          # missing value
```

---

## Commit 2: Add --cloud flag to skip llama-server

A `--cloud` flag (any position) skips starting the local `llama-server`.

Test commands:
```bash
# Cloud model, no local server
opencode --cloud muse-spark-1.3-contributor-free

# Cloud flag in different positions (all identical)
opencode --cloud big-pickle
opencode big-pickle --cloud
opencode big-pickle run "hi" --cloud

# Regression: local model still starts the server
opencode --model qwen3.8-27b

# Regression: subcommands untouched (no server started)
opencode run "hello"
opencode models
```

**Verify cloud mode:**
```bash
# While the command is running, in another terminal:
pgrep -af llama-server || echo "no llama-server (correct for --cloud)"
curl -s http://127.0.0.1:8080/health || echo "no server on 8080 (correct)"
```

Expected: `--cloud` prints `Cloud mode: skipping llama-server`, no server on port 8080.

---

## Commit 3: Add -jinja and --reasoning off to llama-server

The server now always starts with `-jinja --reasoning off`.

Test commands:
```bash
# Local model — verify flags in the log
opencode --model qwen3.8-27b
grep -iE "jinja|reasoning" /tmp/opencode-llama-server.log
```

Expected: `-jinja` and `--reasoning off` are present in the launched command.

---

## Fix: Launch server with requested model (model registry, bare names)

The server launches the correct HF repo for the requested model and aliases it to the short opencode name. The mapping lives in an external JSON file, `models.json`. The user passes a **bare model name** (the key in `models.json`); the wrapper re-attaches the provider prefix internally (`llama.cpp/` or `opencode/`) so opencode can route to it:

```json
{
  "default": {
    "provider": "llama.cpp",
    "name": "qwen3.8-27b"
  },
  "llama.cpp": {
    "qwen3.8-27b": "unsloth/Qwen3.8-27B-GGUF:UD-Q6_K_M",
    "bonsai-27b": "prism-ml/Ternary-Bonsai-2-27B-gguf"
  },
  "opencode": {
    "muse-spark-1.3-contributor-free": "muse-spark-1.3-contributor-free",
    "big-pickle": "big-pickle"
  }
}
```

- `default` — the model a **bare `opencode`** uses. `provider` is `llama.cpp`
  or `opencode`; `name` must be a registered key under that provider.
- To add a model, add a `"name": "<target>"` entry under the right provider key
  (for llama.cpp, also add a matching entry under `provider.llama.cpp.models` in
  `opencode.json`). No wrapper or Nix changes needed.
- To change the default, edit the `default` object (no rebuild required).

Model map (resolved from `models.json`; the prefix is re-attached internally):
| You type | Routed as | Server launches |
|---|---|---|
| *(bare `opencode`)* | default from `models.json` | per default (local: started, cloud: skipped) |
| `--model qwen3.8-27b` | `llama.cpp/qwen3.8-27b` | `unsloth/Qwen3.8-27B-GGUF:UD-Q6_K_M` |
| `--model bonsai-27b` | `llama.cpp/bonsai-27b` | `prism-ml/Ternary-Bonsai-2-27B-gguf` |
| `--model <unknown>` | — | rejected; available models listed |
| *(no model flag; subcommand)* | — | no server started |
| `--cloud <zen>` | `opencode/<zen>` | *(skipped — cloud)* |

Test commands:
```bash
# Echo should now say the correct HF repo
opencode --model qwen3.8-27b
opencode --model bonsai-27b

# Verify the correct model loaded in the log
grep -iE "loading model|hf|alias" /tmp/opencode-llama-server.log

# Bonsai must actually load Bonsai, not Qwen
opencode --model bonsai-27b run "Describe yourself briefly"
```

---

## Quick sanity matrix

| Command | Result | Server? | Behavior |
|---|---|---|---|
| `opencode --model qwen3.8-27b` | OK | started (Qwen) | local |
| `opencode --model bonsai-27b` | OK | started (Bonsai) | local |
| `opencode --model custom` | **REJECTED** (exit 2) | — | local name not in `models.json`; list printed |
| `opencode --cloud big-pickle` | OK | skipped | cloud |
| `opencode run "hi"` | OK | not started | subcommand, no server |
| `opencode models` | OK | not started | subcommand, no server |
| `opencode` | OK | started (Qwen) | bare → default model (`qwen3.8-27b`, local) |
| `opencode qwen3.8-27b` | **REJECTED** (exit 2) | — | positional model, needs `--model` |
| `opencode big-pickle` | **REJECTED** (exit 2) | — | positional cloud, needs `--cloud` |
| `opencode --cloud qwen3.8-27b` | **REJECTED** (exit 2) | — | local-only name passed to `--cloud` |
| `opencode --model big-pickle` | **REJECTED** (exit 2) | — | cloud-only name passed to `--model` |
| `opencode --model a --cloud b` | **REJECTED** (exit 2) | — | mutually exclusive |
| `opencode --model` | **REJECTED** (exit 2) | — | missing value |
| `opencode --cloud not-a-real-model` | **REJECTED** (exit 2) | — | cloud model not in `models.json`; list printed |

---

## Commit: Add MTP speculative decoding + sampling params to llama-server

The local server now always starts with:
`--jinja --reasoning off --parallel 1 --spec-type draft-mtp --temp 0.7 --top-p 0.80 --top-k 20 --min-p 0.0 --presence-penalty 1.5 --repeat-penalty 1.0`

Note: the reference command's `--chat-template-kwargs '{"enable_thinking": false}'` was replaced by `--reasoning off`, the current way to disable thinking (llama.cpp b64739e).

Steps:
1. Rebuild: `just build two-b`
2. Kill any stale server: `pkill -f llama-server || true`
3. Launch a local model: `opencode --model qwen3.8-27b`

Verification (in another terminal while opencode is running):
```bash
# MTP + sampling flags present in the launched command
grep -iE "spec-type|draft-mtp|reasoning|presence-penalty" /tmp/opencode-llama-server.log

# Server reports its loaded models (alias still routes correctly)
curl -s http://127.0.0.1:8080/v1/models | head -50
```

Expected:
- Log shows the server was started with `--spec-type draft-mtp` and `--reasoning off`.
- `/v1/models` lists the alias (`qwen3.8-27b`), so opencode can still route to it.
- opencode completes a prompt (e.g. `opencode --model qwen3.8-27b run "Say hello in 5 words"`).
- MTP speedup (if any) is visible in the server log's token/s stats during generation.

---

## Backend shutdown on last instance exit

The wrapper's EXIT trap stops `llama-swap` (SIGTERM, 20 s wait, SIGKILL
backstop) when the last opencode instance exits — the backend (and its
`llama-server` children) no longer outlives the sessions. A systemd user
timer (`llama-swap-watchdog`, every 30 s) is the safety net for cases the
trap cannot cover: the last instance being the desktop app (which never
runs the wrapper), or a SIGKILLed wrapper. Backends younger than 90 s are
left alone (startup grace), so the watchdog never kills a backend a just
launched instance is still connecting to.

Instance detection matches the `/proc/PID/exe` basename, **not** `comm`:
the kernel truncates `comm` to 15 characters and `opencode-desktop` is 16,
so `pgrep -x`/`comm` comparison can never see the desktop app.

Manual tests (rebuild first: `just build two-b`):
```bash
# Terminal 1: opencode --model qwen3-8b
# Terminal 2 (while the session is open):
pgrep -af 'llama-swap|llama-server'    # backend running
# Close the session in Terminal 1, then:
sleep 2
pgrep -af 'llama-swap|llama-server'    # nothing — backend stopped
```

- Multi-instance: open two local-model sessions, close one → backend
  survives; close the last → backend stops.
- Cloud mode: `opencode --cloud <name>` never starts/stops the backend.
- Desktop last: run a CLI local session, then close `opencode-desktop`
  last → backend is orphaned, watchdog stops it within ~30 s
  (`journalctl --user -u llama-swap-watchdog -n 20`).
- Grace: right after a rebuild, an orphaned < 90 s backend is NOT killed
  by the first watchdog runs.

---

## Commit history (expected)

```
feat(llm-agent): allow model name argument to opencode wrapper
feat(llm-agent): add --cloud flag to skip llama-server
fix(llm-agent): enforce --model/--cloud keywords and launch requested model
feat(llm-agent): launch llama-server with MTP speculative decoding and sampling params
```
