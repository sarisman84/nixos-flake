# Ctx feasibility 120-200k — RTX 5090 32GB + 64GB RAM

Ticket #28 (map #25). Preference: quant-drop → ctx-drop → offload. Targets 120-200k.
Models: `unsloth/Qwen3.8-27B-GGUF:UD-Q6_K_M`, `prism-ml/Ternary-Bonsai-2-27B-gguf`.

## Why 120k+ is feasible: hybrid attention

Qwen3.8-27B (`model_type qwen3_5`): 64 layers, only **16 full Gated Attention**
(`full_attention_interval: 4`), 48 linear Gated DeltaNet (constant recurrent state,
no KV growth). Gated Attention: 4 KV heads × 256 head_dim. Native ctx **262144**.
Bonsai family inherits the same hybrid backbone (~75% linear). Sources:
`https://huggingface.co/Qwen/Qwen3.8-27B`,
`https://zenn.dev/toki_mwc/articles/qwen38-27b-rtx5090-262k-context?locale=en`.

## KV-cache math (per token, batch 1)

Theory: 16 × 4 × 256 × 2 (K,V) = 32768 vals/token → **64 KiB/token f16**.
Measured (Zenn, RTX 5090): **f16 ≈63 KiB/tok, q8_0 ≈34.7 KiB/tok**; q4_0 ≈16 KiB/tok (~1/4).

| ctxSize | f16 KV | q8_0 KV | q4_0 KV |
|---|---|---|---|
| 120k | ~7.2 GiB | ~4.0 GiB | ~1.9 GiB |
| 131072 | ~7.9 GiB | ~4.3 GiB | ~2.0 GiB |
| 200k | ~12.0 GiB | ~6.6 GiB | ~3.1 GiB |
| 262144 | ~15.8 GiB | ~8.7 GiB | ~4.1 GiB |

Rule: `KV ≈ 2(K,V) × 16 layers × 4 heads × 256 dim × ctx × bytes/val`.
Background: `https://locara.dev/docs/notes/llm-memory-math`,
`https://hussain-nazary.github.io/kv-cache-quantization.html`.

## Weights (measured, Zenn)

| Build | Size | Note |
|---|---|---|
| Official FP8 | 30.39 GB = 28.30 GiB | leaves ~3.5 GiB → long ctx impossible |
| `unsloth:Q6_K` (≈UD-Q6_K_M) | ~22.9 GB ≈ 21.3 GiB | ticket's Qwen quant |
| `unsloth:UD-Q4_K_XL` | 17.92 GB ≈ 16.69 GiB | proven 262k |
| Ternary Bonsai-2-27B | ~5.9-7.2 GB | `prism-ml/Ternary-Bonsai-2-27B-gguf` |
| 1-bit Bonsai Q1_0 | ~3.9 GB | current displayName says Q1_0 but hfRef is Ternary — mismatch to fix in #31 |

Usable VRAM: 32607 MiB = **31.84 GiB**, minus ~1-2 GiB resident → **~30 GiB practical**.

## Feasibility table (est VRAM = weights + KV + ~1 GiB runtime)

| Model | Quant | cacheType | ctxSize | Est VRAM | Verdict / flags |
|---|---|---|---|---|---|
| qwen3.8-27b | UD-Q6_K_M | q8_0/q8_0 | 120k | ~26 GiB | ✅ fits; `-c 131072 -ctk q8_0 -ctv q8_0 -fa on` |
| qwen3.8-27b | UD-Q6_K_M | q8_0/q8_0 | 131072 | ~26.6 GiB | ✅ current default feasible |
| qwen3.8-27b | UD-Q6_K_M | q8_0/q8_0 | 200k | ~29 GiB | ✅ tight but fits |
| qwen3.8-27b | UD-Q6_K_M | q4_0/q4_0 | 200k | ~25.4 GiB | ✅ comfortable, small recall loss |
| qwen3.8-27b | UD-Q6_K_M | q8_0/q8_0 | 262144 | ~31 GiB | ⚠️ likely OOM → drop quant first |
| qwen3.8-27b | UD-Q4_K_XL | q8_0/q8_0 | 262144 | **28.1 GiB measured** | ✅ proven (Zenn) |
| bonsai-27b | ternary/Q2 | q8_0/q8_0 | 131072 | ~11 GiB | ✅ huge headroom |
| bonsai-27b | ternary/Q2 | q8_0/q8_0 | 200k | ~13.6 GiB | ✅ |
| bonsai-27b | ternary/Q2 | q8_0/q8_0 | 262144 | ~15.7 GiB | ✅ native max, no quant drop needed |

**Max plausible per preference:** Qwen UD-Q6_K_M → **131-200k @ q8_0**
(262k only after dropping to UD-Q4_K_XL); Bonsai ternary → **262144 @ q8_0**.

## Evidence (similar hardware, 120k+)

- RTX 5090 + Qwen3.8-27B UD-Q4_K_XL + q8_0 KV: 262144 alloc @ 28167 MiB, 63.7 t/s
  empty / 30.4 t/s filled, prefill 267s. Zenn link above.
- RTX 5090: Qwen3-MoE-30B to 147k in 31 GB; Qwen3-32B Q4 to 32-45k;
  Gemma4-31B Q4 to 128k. `https://www.hardware-corner.net/rtx-5090-llm-benchmarks`.
- FitLLM 5090 page: Qwen 3.8 27B ~105k @ Q4+f16-KV baseline (quantized KV pushes
  higher). `https://fitllm.run/can-i-run/what-can-i-run-on-rtx-5090`.
- Reddit 5090 owners: Qwen3-32B Q4/Q5 + Q8 KV @ 32k, 27-60 t/s.
  `https://www.reddit.com/r/LocalLLaMA/comments/1lff4ni/5090_benchmarks_where_are_they`.
- Bonsai paper: 100k ctx @ 14.7 GB (ternary, no KV compression); 134 t/s ternary
  on 5090. `https://prismml.com/news/bonsai-27b`, `https://huggingface.co/prism-ml/Ternary-Bonsai-27B-gguf`.
- vLLM recipe: 1×5090 NVFP4 Qwen3.8-27B @ 262k (fp8 KV), MTP accept ~0.77-0.90.
  `https://recipes.vllm.ai/Qwen/Qwen3.8-27B`.

## llama-server flags the schema must expose

Source: `https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md`.

- `-c/--ctx-size` (total KV budget across `--parallel` slots, not per-request).
- `-ctk/--cache-type-k`, `-ctv/--cache-type-v`: `f32 f16 bf16 q8_0 q4_0 q4_1 iq4_nl q5_0 q5_1`, default f16.
  q8_0 ≈ lossless; q4_0 ≈ 4× saving, small recall loss. Split K/V (don't collapse to one `cacheType`).
- `-fa/--flash-attn on|off|auto` — **required on for quantized V**.
- `--reasoning-budget N` (`-1` unlimited, `0` immediate end) + `--reasoning-budget-message`.
- MTP/speculative: `--spec-type draft-mtp`, `-md/--model-draft`, `--spec-draft-n-max`
  (Qwen MTP n=3 optimal, 1.54×, 53.8% accept; n=5 regresses),
  `--ctx-size-draft`, `-ctkd/-ctvd` draft cache types. Bonsai ships DSpark drafter (1.34×).
  Docs: `https://github.com/ggml-org/llama.cpp/blob/master/docs/speculative.md`.
- Also: `-ngl/--n-gpu-layers` (full offload = no CPU spill per preference),
  `-np/--parallel`, `-b/--batch-size`, `-ub/--ubatch-size`, `--jinja`, `--mmproj` (+1.4 GiB).

## Caveats for #29 (baseline) and #31 (schema)

- Empty-ctx alloc benchmarks lie (63.7 vs 30.4 t/s); must fill ctx when measuring.
- 262k prefill ≈ 4.5 min — "runs" ≠ "interactive".
- `llama-perplexity` @131k needs ~130 GB RAM (vocab 248320 logits) — use needle tests instead.
- MTP + 262k simultaneously OOMs on 32 GB (draft ~2.6 GiB) — choose speed XOR max ctx.
- Fix Bonsai `displayName` (says Q1_0, hfRef is Ternary) in schema ticket.
