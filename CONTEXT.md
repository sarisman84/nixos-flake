# Context: Local LLM Serving

How local models are served, swapped, and de-allocated on this machine. Vocabulary for the `llm-agent` module.

## Language

### The registry

**model entry**
A single model configuration in the JSON registry. Identity is the **model key**; `displayName` is cosmetic and never transmitted. `hfRef` and `options` are the other fields. All tunables live under `options`.
_Avoid_: model, local model

**model key**
The registry key of a model entry. The identity sent on the wire and matched by the backend; must equal the backend's model ID.
_Avoid_: id, name, model name

**displayName**
Human-readable label for a model entry, shown in the model selector. Cosmetic; never sent to the backend.
_Avoid_: model name, alias, title

**hfRef**
HuggingFace model reference (e.g. `"unsloth/Qwen3.8-27B-GGUF:UD-Q6_K_M"`). Determines weights, quantization, and memory footprint.

**options**
Sub-object holding every tunable for a model entry. All fields optional; unset values fall back to defaults.
_Avoid_: config, settings, params

**ctxSize**
Server-side context window in tokens.
_Avoid_: context window, context length

**outputLimit**
Client-side output token budget hint. Never sent to the backend.
_Avoid_: maxTokens, maxOutputTokens

**reasoningBudget**
Cap on thinking tokens per response. `null` = unrestricted.
_Avoid_: thinking budget, reasoning tokens

**cacheTypeK / cacheTypeV**
Split KV-cache quantization formats. Determines memory footprint per token of context. Bare `cacheType` is shorthand for both. Quantized `cacheTypeV` requires flash attention.

**mtpProfile**
Multi-Token Prediction tuning. Speed XOR max context, never implicit.

**efficient model**
A model entry chosen for capability rather than cost: large context, reasoning budget enabled. The opposite of a **cheap model**.
_Avoid_: reasoning model, big model, premium model

**cheap model**
A model entry chosen for cost rather than capability: small context, no reasoning budget. Used where quality is not load-bearing.
_Avoid_: efficient model, small model, fast model, light model

### Runtime

**backend**
The long-lived process that fronts all local models and owns the local endpoint. Always up. Not the thing that costs resources.
_Avoid_: server, proxy, daemon

**resident model**
The one model entry currently held in memory by the backend. At most one at a time. The unit of resource de-allocation.
_Avoid_: loaded model, warm model, active model, current model

**swap**
Replacing the resident model with another. Costs a full unload and reload; there is no partial or warm variant.
_Avoid_: reload, rotate, switch, cycle

**swap group**
The set of model entries the backend may hold one of at a time. A request for a member evicts the resident model when it is a different member.
_Avoid_: exclusivity group, one-resident set, pool

**idle**
No pending inference against the backend. A measure of what a *user* is doing, not of traffic: a session being read is not idle, however quiet the backend is.
_Avoid_: inactive, dormant, cold, unused

**ttl**
Seconds of backend-side inactivity after which the resident model is unloaded. `0` never evicts. A failsafe floor only — the **idle** policy is owned elsewhere.
_Avoid_: timeout, expiry, lease

**hardware profile**
RTX 5090 (32 GB VRAM), 64 GB system RAM, Ryzen 9950X3D. Constrains the maximum feasible `ctxSize` for a given weight size and `cacheType` combination.

---

Decisions are recorded in [`docs/adr/`](./adr/). Registry structure is in [`docs/llm-agent/registry.md`](./llm-agent/registry.md).
