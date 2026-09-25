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

```bash
opencode --model llama.cpp/<name>   # local model (starts llama-server)
opencode --cloud opencode/<name>    # cloud model (skips llama-server)
opencode [opencode args...]         # subcommands only (models, run, mcp, ...)
```

- `--model` takes any `llama.cpp/<name>`; the name is looked up in
  `llama-models.json` (the model registry) to find the HF repo to launch.
  Unknown names fall back to default Qwen with a warning.
- `--cloud` takes an `opencode/<name>` (OpenCode Zen) and skips the local server.
- `--model` and `--cloud` are mutually exclusive.
- A **bare `opencode`** (no flag, no subcommand) is rejected (exit 2).
- Subcommands without a model flag (`models`, `run`, `mcp`, …) are allowed and
  use the default local model.

Test commands:
```bash
# Local models (must use --model)
opencode --model llama.cpp/qwen3.8-27b
opencode --model llama.cpp/bonsai-27b

# Cloud model (must use --cloud)
opencode --cloud opencode/muse-spark-1.3-contributor-free

# Model + one-shot prompt
opencode --model llama.cpp/qwen3.8-27b run "Say hello in 5 words"
opencode --cloud opencode/big-pickle run "Say hi"

# Subcommands (no model flag; default local)
opencode run "hello"
opencode models

# Rejected (should print usage, exit 2):
opencode                                   # bare, no mode
opencode llama.cpp/qwen3.8-27b            # positional model, no --model
opencode opencode/big-pickle              # positional cloud, no --cloud
opencode --cloud llama.cpp/qwen3.8-27b    # --cloud with a local model
opencode --model opencode/big-pickle      # --model with a cloud model
opencode --model llama.cpp/a --cloud opencode/b   # both flags
opencode --model                          # missing value
```

---

## Commit 2: Add --cloud flag to skip llama-server

A `--cloud` flag (any position) skips starting the local `llama-server`.

Test commands:
```bash
# Cloud model, no local server
opencode --cloud opencode/muse-spark-1.3-contributor-free

# Cloud flag in different positions (all identical)
opencode --cloud opencode/big-pickle
opencode opencode/big-pickle --cloud
opencode opencode/big-pickle run "hi" --cloud

# Cloud-only (uses config default; skips server)
opencode --cloud

# Regression: local model still starts the server
opencode llama.cpp/qwen3.8-27b

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
opencode llama.cpp/qwen3.8-27b
grep -iE "jinja|reasoning" /tmp/opencode-llama-server.log
```

Expected: `-jinja` and `--reasoning off` are present in the launched command.

---

## Fix: Launch server with requested model (model registry)

The server now launches the correct HF repo for the requested `llama.cpp/<model>` and aliases it to the short opencode name. The mapping lives in an external JSON file, `llama-models.json`, instead of a hardcoded case statement:

```json
{
  "llama.cpp": {
    "qwen3.8-27b": "unsloth/Qwen3.8-27B-GGUF:UD-Q6_K_M",
    "bonsai-27b": "prism-ml/Ternary-Bonsai-2-27B-gguf"
  }
}
```

To add a model, add a `"name": "<hf-repo>"` entry under `llama.cpp` in `llama-models.json` (and a matching entry under `provider.llama.cpp.models` in `opencode.json`). No wrapper or Nix changes needed.

Model map (for `--model` values; resolved from `llama-models.json`):
| You type | Server launches | Aliased as |
|---|---|---|
| `--model llama.cpp/qwen3.8-27b` | `unsloth/Qwen3.8-27B-GGUF:UD-Q6_K_M` | `qwen3.8-27b` |
| `--model llama.cpp/bonsai-27b` | `prism-ml/Ternary-Bonsai-2-27B-gguf` | `bonsai-27b` |
| `--model llama.cpp/<unknown>` | default Qwen (warning to stderr) | `<unknown>` |
| *(no `--model`; subcommand)* | `unsloth/Qwen3.8-27B-GGUF:UD-Q6_K_M` | `qwen3.8-27b` |
| `--cloud opencode/<zen>` | *(skipped — cloud)* | — |

Test commands:
```bash
# Echo should now say the correct HF repo
opencode --model llama.cpp/qwen3.8-27b
opencode --model llama.cpp/bonsai-27b

# Verify the correct model loaded in the log
grep -iE "loading model|hf|alias" /tmp/opencode-llama-server.log

# Bonsai must actually load Bonsai, not Qwen
opencode --model llama.cpp/bonsai-27b run "Describe yourself briefly"
```

---

## Quick sanity matrix

| Command | Result | Server? | Behavior |
|---|---|---|---|
| `opencode --model llama.cpp/qwen3.8-27b` | OK | started (Qwen) | local |
| `opencode --model llama.cpp/bonsai-27b` | OK | started (Bonsai) | local |
| `opencode --model llama.cpp/custom` | OK | started (Qwen) | local, unknown → default + warning |
| `opencode --cloud opencode/big-pickle` | OK | skipped | cloud |
| `opencode run "hi"` | OK | started (Qwen) | subcommand, default local |
| `opencode models` | OK | started (Qwen) | subcommand, default local |
| `opencode` | **REJECTED** (exit 2) | — | bare, no mode |
| `opencode llama.cpp/qwen3.8-27b` | **REJECTED** (exit 2) | — | positional model, needs `--model` |
| `opencode opencode/big-pickle` | **REJECTED** (exit 2) | — | positional cloud, needs `--cloud` |
| `opencode --cloud llama.cpp/qwen3.8-27b` | **REJECTED** (exit 2) | — | `--cloud` needs `opencode/<name>` |
| `opencode --model opencode/big-pickle` | **REJECTED** (exit 2) | — | `--model` needs `llama.cpp/<name>` |
| `opencode --model a --cloud b` | **REJECTED** (exit 2) | — | mutually exclusive |
| `opencode --model` | **REJECTED** (exit 2) | — | missing value |

---

## Commit: Add MTP speculative decoding + sampling params to llama-server

The local server now always starts with:
`--jinja --reasoning off --parallel 1 --spec-type draft-mtp --temp 0.7 --top-p 0.80 --top-k 20 --min-p 0.0 --presence-penalty 1.5 --repeat-penalty 1.0`

Note: the reference command's `--chat-template-kwargs '{"enable_thinking": false}'` was replaced by `--reasoning off`, the current way to disable thinking (llama.cpp b64739e).

Steps:
1. Rebuild: `just build two-b`
2. Kill any stale server: `pkill -f llama-server || true`
3. Launch a local model: `opencode --model llama.cpp/qwen3.8-27b`

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
- opencode completes a prompt (e.g. `opencode --model llama.cpp/qwen3.8-27b run "Say hello in 5 words"`).
- MTP speedup (if any) is visible in the server log's token/s stats during generation.

---

## Commit history (expected)

```
feat(llm-agent): allow model name argument to opencode wrapper
feat(llm-agent): add --cloud flag to skip llama-server
fix(llm-agent): enforce --model/--cloud keywords and launch requested model
feat(llm-agent): launch llama-server with MTP speculative decoding and sampling params
```
