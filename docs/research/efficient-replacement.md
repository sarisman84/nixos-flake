# Research: stock-compatible efficient-path replacement for bonsai-27b

Ticket: #33 (map #25). Scope: HF + stock-llama.cpp compat only. No downloads, no config edits.
Date: 2026-09-28. Upstream: Hugging Face model pages (Qwen, unsloth, prism-ml), prism-ml docs.

## 1. Bonsai fork requirement — CONFIRMED (primary sources)

- HF model card `prism-ml/Ternary-Bonsai-2-27B-gguf`, Quickstart section
  "These files need our llama.cpp build": **"Stock llama.cpp will not run
  these files.** It rejects `PQ2_0` and `PTQ1_0` as unknown types, and it
  loads `Q2_0` without any warning and produces garbage, because it has no
  Hadamard activation runtime. Use a binary from the fork."
  Source: https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf
- `KNOWN_ISSUES.md` in the same repo: "`PQ2_0` and `PTQ1_0` are new
  quantization types, and support for them isn't in mainline llama.cpp yet.
  ... Stock llama.cpp, Ollama and LM Studio (GGUF) can't load the `PQ2_0` or
  `PTQ1_0` files." / workaround: "use the PrismML llama.cpp build".
  Source: https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/blob/main/KNOWN_ISSUES.md
- prism-ml docs name the demo repo (`PrismML-Eng/Bonsai-demo`) the source of
  truth and pin fork binaries; the `prism` branch of `PrismML-Eng/llama.cpp`
  is required for ternary `Q2_0`.
  Sources: https://docs.prismml.com/run/llamacpp,
  https://github.com/PrismML-Eng/Bonsai-demo

Conclusion: `bonsai-27b` (`prism-ml/Ternary-Bonsai-2-27B-gguf`) is out for the
stock-llama.cpp flake, as the map already ruled. (For the record it is a
reasoning model — `xhigh` effort by default — 5.95 GB PTQ1_0 / 7.21 GB PQ2_0,
262K ctx; irrelevant given the fork requirement.)

## 2. Efficient-path budget (from #33 + map #25)

- Stock-llama.cpp-compatible GGUF instruct (non-reasoning) model on HF.
- Resident footprint weights + KV well under ~10 GiB at target ctx; cold
  load in seconds (evict-then-load, one-resident `swap: true, exclusive:
  true`); ctx 32–64k is fine.
- Reasoning path is locked: `unsloth/Qwen3.8-27B-GGUF:UD-Q6_K_M` at 131–200k
  ctx. Reference point from #29 (map #25): Qwen-27B ≈23.9 GiB resident at
  32k (≈24.4 GiB at 64k), ~4 s cold load. An 8B model at 32k lands roughly a
  third of that all-in — inside budget with headroom.

## 3. Ranked candidates (all primary-sourced)

| # | hfRef | Weights | Native ctx | Instruct? | Stock llama.cpp? | Fit |
|---|---|---|---|---|---|---|
| 1 (recommended) | `unsloth/Qwen3-8B-GGUF:UD-Q4_K_XL` | 5.14 GB | 32,768 (YaRN to 131,072) | Yes — `enable_thinking=False` / `/no_think` = pure instruct, Qwen2.5-Instruct-class behavior | Yes — unsloth's own default in its stock `llama serve -hf …` instructions (ggerganov releases) | ≈7–8 GiB resident at 32k (weights + GQA KV: 36 layers, 8 KV heads); fastest cold load (~5 GB file); same vendor + chat-template family as the locked reasoning path |
| 2 (quality upscale) | `unsloth/Qwen3-8B-GGUF:UD-Q6_K_XL` | 7.49 GB | 32,768 (YaRN to 131,072) | Same as #1 (same base model) | Same as #1 | Better weights quality; still fits at 32k with q4 KV (≈8.5–9 GiB). Pick if #1 underperforms on agentic coding; costs ~2.3 GB extra + slower load |
| 3 (vendor-official fallback) | `Qwen/Qwen3-8B-GGUF:Q6_K` | 6.73 GB | 32,768 (YaRN to 131,072) | Same toggle (`/think` / `/no_think`) | Yes — Qwen's official page gives stock `llama-cli -hf Qwen/Qwen3-8B-GGUF:…` commands | Same model, official (non-Dynamic) quant; slightly lower quant quality than Dynamic XL. Fallback if unsloth files are ever unavailable |
| Rejected (borderline) | `unsloth/Qwen3-14B-GGUF:UD-Q4_K_XL` | 9.16 GB weights alone | 32,768 (YaRN to 131,072) | Same toggle | Yes (same publishers) | Weights alone ≈9.2 GB; +KV breaks the well-under-10 GiB budget at 32k+. Only viable with reduced ctx/offload — contradicts the efficient-path brief |

Why Qwen3-8B and not another family: the efficient path keeps the Qwen
thinking-toggle semantics (`enable_thinking=False` gives a true
non-reasoning instruct mode), the sampling presets are documented per mode
(non-thinking: `Temperature=0.7, TopP=0.8, TopK=20, MinP=0`), tool-calling
support is the same agent stack as the reasoning path, and stock-llama.cpp
support is documented by both publishers. No Qwen3.8-generation 8B sibling
exists, so the efficient path steps one generation back — acceptable since
the map lets the efficient ctx stay smaller.

## 4. Recommendation

- Pick: **`unsloth/Qwen3-8B-GGUF:UD-Q4_K_XL`** at **32k ctx**, run
  non-thinking (`enable_thinking=False` / `/no_think`) for the efficient
  path. Fallback quant in the same repo: `UD-Q6_K_XL` (quality upscale).
- Downstream: #31 (schema-lock) and #32 (prototype) should use this `hfRef`;
  replacement-model baseline measurement (map "Not yet specified") applies to
  this pick once #33 lands.

## Sources

- https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf (fork
  requirement, Bonsai sizes/ctx/reasoning behavior)
- https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/blob/main/KNOWN_ISSUES.md
- https://docs.prismml.com/run/llamacpp
- https://huggingface.co/unsloth/Qwen3-8B-GGUF (UD-Q4_K_XL 5.14 GB,
  UD-Q6_K_XL 7.49 GB file list; 8.2B/36-layer/GQA-8KV/32k-native spec;
  thinking toggle; stock llama.cpp instructions)
- https://huggingface.co/Qwen/Qwen3-8B-GGUF (Q6_K 6.73 GB; 32k native + YaRN
  131k; stock `llama-cli -hf …` quickstart; non-thinking sampling preset)
- https://huggingface.co/unsloth/Qwen3-14B-GGUF (UD-Q4_K_XL 9.16 GB file;
  14.8B/32k-native spec — basis for rejection)
- Map #25 / ticket #33 for budgets, #29 numbers, and downstream consumers
  (#31, #32).
