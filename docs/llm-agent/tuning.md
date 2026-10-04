# llm-agent model tuning

Tuning is a registry edit: every knob is an `options` field in a `models/<key>.json` file ([registry.md](./registry.md)), and `default.nix` bakes it into the generated `llama-server` command. `nix flake check` validates entries; `config build two-b` deploys.

Tiers run easy to hard. Start at T0; go deeper only with a symptom (OOM, loops, slowness, wrong temperature).

## T0 — pick the entry

Recommended settings for the current registry on this hardware (RTX 5090, 32 GB VRAM):

| Entry | Role | ctx | KV | Sampling | Notes |
|---|---|---|---|---|---|
| `qwen3-30b-a3b` | default, agentic coding | 131k | q4_0 | temp 0.2 | ~3B-active MoE; fastest resident |
| `qwen3-30b-a3b-200k` | long context | 200k | q4_0 | temp 0.2 | 25.1 GB total, 7 GB headroom |
| `qwen3-30b-a3b-ngram` | speculative variant | 131k | q4_0 | temp 0.2 | `ngram-mod`; zero extra VRAM |
| `qwen3.8-27b` | reasoning | 131k | q4_0 | temp 0.4 | reasoning budget 2048 |
| `qwen3.8-27b-200k` | reasoning, long ctx | 200k | q4_0 | temp 0.4 | #55: q8_0 KV OOMs at 200k |
| `gpt-oss-20b` | reasoning alternative | 131k | q8_0 | 1.0 / 1.0 / 64 / 0.0 | vendor set; `--reasoning-effort low` |
| `mistral-small-3.2-24b` | dense alternative | 131k | q4_0 | temp 0.3 | — |
| `qwen3.6-35b-a3b` | replacement candidate, thinking | 131k | q4_0 | 0.6 / 0.95 / 20 | research #1; budget 2048; verify `qwen35moe` loads |
| `qwen3.6-35b-a3b-nt` | replacement candidate, non-thinking | 131k | q4_0 | 0.7 / 0.80 / 20 | vendor non-thinking preset; budget 0 |
| `qwen3.6-35b-a3b-cold` / `-hot` | temp sweep 0.2 / 1.0 | 131k | q4_0 | 0.2 / 1.0 | same vendor p/k; `-hot` tests loop robustness |
| `qwen3.6-35b-a3b-262k` | full native context | 262k | q4_0 | 0.6 / 0.95 / 20 | DeltaNet arch: KV ~2.0 GB, ~5.4 GB headroom |
| `qwen3.6-35b-a3b-ngram` | speed variant | 131k | q4_0 | 0.6 / 0.95 / 20 | `ngram-mod`; zero extra VRAM |
| `glm-4.7-flash` | headroom candidate | 131k | q4_0 | temp 0.4 | budget 2048; 10.5 GB headroom; no vendor preset |
| `glm-4.7-flash-hot` | temp sweep 1.0 | 131k | q4_0 | 1.0 / 0.95 | loop/degeneration lever |
| `glm-4.7-flash-200k` | long context | 200k | q4_0 | temp 0.4 | ~24.6 GB total, 7.4 GB headroom |
| `devstral-small-2-24b` | dense candidate | 131k | q4_0 | temp 0.3 | successor to `mistral-small-3.2-24b`; `--no-mmproj` |
| `devstral-small-2-24b-hot` | temp sweep 1.0 | 131k | q4_0 | 1.0 / 0.95 | loop/degeneration lever |

Choosing: agentic coding → A3B family (fast, cheap to iterate). Hard reasoning → 27B family. Long documents → the 200k entries (A3B first; it is the better long-context citizen — see T2). The `qwen3.6-35b-a3b*`, `glm-4.7-flash*`, and `devstral-small-2-24b*` rows are unverified research candidates ([research note](../research/balanced-model-replacement.md) on branch `research/balanced-model-replacement`): check the server log per "Verifying a change" before use, and do not make one the default until measured against the current entries.

## T1 — temperature

The server-side CLI flag is the effective baseline: opencode sends **no** sampling params for these custom models (the model-entry `temperature` field is a boolean capability flag, not a value, and no agent sets one), so the `--temperature` baked into the command is what takes effect. An agent-level `temperature` in opencode config, when set, overrides per session.

| Range | Behavior | Use for |
|---|---|---|
| 0.0–0.2 | Deterministic | code edits, refactors, structured output |
| 0.3–0.6 | Balanced | general work, reasoning models |
| 0.7–1.0 | Varied | creative work; some models' vendor default |

Per-model values live in the T0 table. If a reasoning model loops or degenerates, raise its temperature; if it spurious-rewrites, lower it.

## T2 — context and KV budget

```
VRAM = weights + KV cache + compute buffer (~1.5 GB) + CUDA context (~0.7 GB)
KV bytes = 2 × layers × kv_heads × head_dim × ctx × bytes_per_element
```

KV memory is linear in context **and** cache precision — `q4_0` halves `q8_0`'s cache. KV sizes for the two architectures in the registry:

| | 131k q4_0 | 131k q8_0 | 200k q4_0 | 200k q8_0 |
|---|---|---|---|---|
| 30B-A3B (48 layers, 4 KV heads) | 3.2 GB | 6.4 GB | 4.9 GB | 9.8 GB |
| 27B dense (64 layers, 8 KV heads) | 8.6 GB | 17.2 GB | 13.1 GB | 26.2 GB |

History and rules from #55:

- The 27B cannot do 200k with headroom at any quant — q8_0 overruns the 5090 by ~6.6 GB and never loads. Its 200k entry is q4_0.
- The A3B **can** do 200k at q8_0 (30.0 GB total) but leaves ~2 GB headroom — fragile for long sessions. Its 200k entry uses q4_0 (25.1 GB total, 7 GB headroom). If quality ever needs it, the documented upgrade path is flipping `cacheTypeK`/`cacheTypeV` to q8_0 and re-verifying the load.
- KV size scales with layer and KV-head count, not active parameters — that is why the MoE A3B out-caches the dense 27B.

When an entry OOMs, check whether context and cache precision changed together. Reduce in this order: KV precision (q8_0 → q4_0), then context, then weight quant (Q6 → Q5 → Q4) — cutting quant hurts quality more than cutting context.

Set context to what the workload needs: agentic sessions accumulate tool output (131k is ample), long-document work pays the KV cost linearly. An oversized context also slows attention.

## T3 — the sampling set

Beyond temperature, the registry exposes `topP` (default 0.95), `topK` (40), `minP` (0.05) → `--top-p`/`--top-k`/`--min-p`. Touch them only with a symptom:

- **Vendor requirements** — gpt-oss-20b runs its card's recommended sampling (1.0/1.0/64/0.0); this is why the knobs exist as per-entry values rather than a global.
- **Degenerate repetition** — a small `minP` floor or a higher temperature usually fixes it.
- **Over-truncation / blandness** — raise `topP`.

Do not tune past temperature without a measured problem.

## T4 — speculative decoding (`specProfile`)

Speculative decoding trades VRAM for speed: a drafter proposes tokens, the main model verifies in one pass. It is **speed XOR max context** — a draft model adds its own weights and KV cache, so never combine speculative decoding with a maxed-out context on tight VRAM.

`specType` is validated against the llama.cpp `--spec-type` list (v0.5.0):

| Type | Extra VRAM | Notes |
|---|---|---|
| `ngram-*` (`-simple`, `-map-k`, `-map-k4v`, `-mod`, `-cache`) | none | no drafter; n-grams from the context. `ngram-mod` is llama.cpp's recommended type for agentic code work and reasoning-model repetition. This is the `qwen3-30b-a3b-ngram` entry |
| `draft-simple`, `draft-eagle3` | draft model | needs `draftModel`; `draft-eagle3` needs matching heads |
| `draft-mtp` | none (heads are in the model) | needs MTP heads inside the GGUF — unverified for the Qwen3.8-27B UD quants, so it stays `enabled: false` everywhere until proven |
| `draft-dflash`, `draft-dspark` | draft model | newer drafters; same `draftModel` machinery |

Draft-model knobs (all optional, server defaults noted in the verified table below): `draftModel`, `draftTokensMax` → `--spec-draft-n-max`, `draftPMin`/`draftPSplit` → `--spec-draft-p-min`/`--spec-draft-p-split`, `draftGpuLayers` → `--spec-draft-ngl` (`-1` = all), `draftCacheTypeK`/`draftCacheTypeV` → `--cache-type-k/v-draft`.

ngram-specific parameters (n-match/n-min/n-max, defaults 24/48/64) are not schema fields yet; pass them raw when you actually tune:

```json
"extraArgs": ["--flash-attn", "on", "--spec-ngram-mod-n-match", "32"]
```

## Verified flags (llama.cpp v0.5.0, build 11146)

Defaults as printed by the v0.5.0 server docs, verified against the source the flake actually builds:

| Flag | Default |
|---|---|
| `--temperature` | 0.80 |
| `--top-p` / `--top-k` / `--min-p` | 0.95 / 40 / 0.05 |
| `--reasoning-effort` | default (template) |
| `--spec-type` | none |
| `--spec-draft-n-max` | 3 |
| `--spec-draft-p-split` / `--spec-draft-p-min` | 0.10 / 0.00 |
| `--spec-draft-ngl` | auto |
| `--cache-type-k/v-draft` | f16 |

`llama-cpp` tracks nixos-unstable (AGENTS.md), so re-verify this table and `default.nix`'s `validSpecTypes` after `nix flake update`. `--ctx-size-draft` does not exist; the registry used to generate it via `draftCtxSize`, which was removed.

## Verifying a change

`nix flake check` proves the entry validates; it does not prove the model loads. After deploying, check the server log for actual allocation:

```bash
grep -iE 'n_kv|n_ctx|compute buffer|VRAM|total' ~/.config/nixos-flake/users/spyro/modules/productivity/llm-agent/logs/opencode-llama-server.log | tail -20
```

If the server reduced context or offloaded layers, it says so — that line is the ground truth. Then measure tokens/s before and after; if prefill collapsed, the context increase is too aggressive.
