# Context: LLM Setup Optimization (Updated)

## Glossary (updated per user input)

**model entry**
A single model configuration in the JSON registry. Minimum fields: `displayName` (alias) and `hfRef` (HuggingFace URL). All other settings live under an `options` sub-object.

**hfRef**
HuggingFace model reference string (e.g., "unsloth/Qwen3.8-27B-GGUF:UD-Q6_K_M"). Determines the model weights, quantization, and context footprint.

**displayName**
Human-readable name/alias for the model entry, shown in the opencode client UI.

**options**
A sub-object containing all configurable server flags. Currently supports: `ctxSize`, `outputLimit`, `gpuLayers`, `cacheTypeK`, `cacheTypeV` (plus `cacheType` shorthand setting both), `templateOverride`, `ttl`, `reasoningBudget`, `mtpProfile`, `extraArgs`. All fields are optional - unset values fall back to safe defaults.

**ctxSize**
Server-side context window size in tokens. Locked defaults: 131072 reasoning, 65536 efficient (minimum viable under the harness request overhead — 32768 starves it into a compact loop), 200000 as a second opt-in entry. Falls back to 65536 (64k) safe default when unset.

**outputLimit**
Opencode-local output token budget hint per model (never sent to the server). Falls back to 16384 when ctxSize >= 65536, else 8192.

**reasoningBudget**
Cap on thinking tokens per response (via `--reasoning-budget` flag). Default: 2048 on the reasoning path, 0 (immediate end of thinking) on non-thinking efficient path. Null = server default (unrestricted).

**mtpProfile**
Multi-Token Prediction configuration profile. Optional object under `options`, default off (speed XOR max context, never implicit).

**llama-swap**
The llama-swap proxy server that serves models locally via HTTP.

**maxCtxSize**
Maximum-context opt-in ceiling (null = no maximum profile).

**hardware profile**
RTX 5090 (32GB VRAM) + 64GB system RAM + Ryzen 9950X3D. Constrains maximum feasible ctxSize for given cacheType and model size.

**cacheTypeK / cacheTypeV**
Split KV-cache quantization formats for K and V (e.g., "q4_0"); `-fa on` required with quantized V. Bare `cacheType` remains as shorthand setting both. Determines memory footprint per token of context.

**efficient model**
Quantized GGUF model balancing context size and quality within hardware constraints.

## JSON Config Structure

Minimum object per model:
```json
{
  "displayName": "Alias name",
  "hfRef": "unsloth/Qwen3.8-27B-GGUF:UD-Q6_K_M",
  "options": {
    "ctxSize": 131072,
    "reasoningBudget": 2048,
    "cacheTypeK": "q4_0",
    "cacheTypeV": "q4_0"
  }
}
```

- `displayName` and `hfRef` are required
- `options` is an optional object; unset fields use safe defaults
- ctxSize target range: 120-200k tokens (user-specified)
- Mixture of automatic defaults + override capability (Q4)

## Key Relationships

- **model entry** → `hfRef` determines model weights; `options.ctxSize` sets context window
- **ctxSize** + **cacheTypeK/V** → combined memory footprint constrains by VRAM (32GB) + RAM (64GB)
- **options** sub-object → all server flags live here; unspecified values auto-default
- **hardware profile** → 32GB VRAM limits max ctxSize for quantized models; 64GB RAM provides overflow offload

## Design Rationale

Moving from Nix options to JSON with `options` sub-object because:
1. JSON is language-agnostic and manually editable
2. `displayName`/`hfRef` minimum object as requested; other settings grouped under `options`
3. Automatic defaults when `options` fields are omitted; explicit override when set
4. Supports the 120-200k ctxSize range with hardware-aware fallbacks

---
*Updated from domain modeling session. User answers: Q1=displayName/url + options object, Q2=separate options object, Q3=120-200k context, Q4=mixed auto+override, Q5=open to recommendations. Last updated: 2026-09-28*