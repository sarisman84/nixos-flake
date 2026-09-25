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
opencode --model <name>    # local model (starts llama-server)
opencode --cloud <name>    # cloud model (skips llama-server)
opencode [opencode args...]  # subcommands only (models, run, mcp, ...)
```

- `--model` takes a name that must be a key under `llama.cpp` in
  `models.json`; the wrapper looks up its HF repo to launch.
  Unknown names are rejected and the available models are listed.
- `--cloud` takes a name that must be a key under `opencode` in
  `models.json`; unknown names are rejected and the available models are listed.
- `--model` and `--cloud` are mutually exclusive.
- A **bare `opencode`** (no flag, no subcommand) is rejected (exit 2).
- Subcommands without a model flag (`models`, `run`, `mcp`, …) are allowed and
  use the default local model.

Test commands:
```bash
# Local models (must use --model)
opencode --model qwen3.8-27b
opencode --model bonsai-27b

# Cloud model (must use --cloud)
opencode --cloud big-pickle

# Model + one-shot prompt
opencode --model qwen3.8-27b run "Say hello in 5 words"
opencode --cloud big-pickle run "Say hi"

# Subcommands (no model flag; default local)
opencode run "hello"
opencode models

# Rejected (should print usage/available models, exit 2):
opencode                                  # bare, no mode
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

# Regression: subcommands untouched
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

To add a model, add a `"name": "<target>"` entry under the right provider key in `models.json` (for llama.cpp, also add a matching entry under `provider.llama.cpp.models` in `opencode.json`). No wrapper or Nix changes needed.

Model map (resolved from `models.json`; the prefix is re-attached internally):
| You type | Routed as | Server launches |
|---|---|---|
| `--model qwen3.8-27b` | `llama.cpp/qwen3.8-27b` | `unsloth/Qwen3.8-27B-GGUF:UD-Q6_K_M` |
| `--model bonsai-27b` | `llama.cpp/bonsai-27b` | `prism-ml/Ternary-Bonsai-2-27B-gguf` |
| `--model <unknown>` | — | rejected; available models listed |
| *(no `--model`; subcommand)* | — | `unsloth/Qwen3.8-27B-GGUF:UD-Q6_K_M` |
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
| `opencode run "hi"` | OK | started (Qwen) | subcommand, default local |
| `opencode models` | OK | started (Qwen) | subcommand, default local |
| `opencode` | **REJECTED** (exit 2) | — | bare, no mode |
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

## Commit history (expected)

```
feat(llm-agent): allow model name argument to opencode wrapper
feat(llm-agent): add --cloud flag to skip llama-server
fix(llm-agent): enforce --model/--cloud keywords and launch requested model
feat(llm-agent): launch llama-server with MTP speculative decoding and sampling params
```
