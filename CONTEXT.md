# Context

Domain vocabulary for this machine's tooling. Two areas: **local LLM serving** (how local models are served, swapped, and de-allocated; the `llm-agent` module) and **Unity tooling** (the CLI, Editor, and agent skills used to build Unity projects).

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

**specProfile**
Speculative decoding tuning — any `--spec-type` (draft-*, ngram-*, MTP), not just Multi-Token Prediction. `specType` is validated against the llama.cpp flag list. Speed XOR max context, never implicit.

**sampling params**
`temperature`, `topP`, `topK`, `minP`. Baked into the `llama-server` command as the server-side baseline: opencode sends no sampling params for custom models, so the CLI values are what takes effect. An agent-level `temperature` overrides per session.

**efficient model**
A model entry chosen for capability rather than cost: reasoning enabled (a reasoning budget, or a reasoning model). The opposite of a **cheap model**.
_Avoid_: reasoning model, big model, premium model

**cheap model**
A model entry chosen for cost rather than capability: no reasoning. Context size is chosen independently — a cheap model can carry a large context. Used where quality is not load-bearing.
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

**lease**
One opencode instance's published claim on the **resident model**: what it is doing, and how long since it last did anything local. A lease is a statement of intent, not proof of anything. A lease whose process no longer exists is **stale**, and a stale lease constrains nothing.
_Avoid_: lock, claim, token, heartbeat

**unload policy**
The rule that decides when the **resident model** may be released, and the one question it answers: is it safe to unload right now? Every input it consults is published state, never a direct observation of another instance.
_Avoid_: reaper, evictor, janitor, watchdog

**settle delay**
The interval a reported **idle** must stand still before it is believed. Exists because a turn's opening request is in flight before the session is marked busy.
_Avoid_: debounce, grace period, hysteresis

**heartbeat**
A written record that the policy loaded and is still running. Distinguishes "the policy decided not to unload" from "the policy does not exist".
_Avoid_: ping, keepalive, liveness probe

**hardware profile**
RTX 5090 (32 GB VRAM), 64 GB system RAM, Ryzen 9950X3D. Constrains the maximum feasible `ctxSize` for a given weight size and `cacheType` combination.

### Unity tooling

**Unity CLI**
The standalone `unity` command-line tool that manages Unity editors, projects, and licenses, and drives a running Editor. It is the interface to Unity on this machine, replacing Unity Hub.
_Avoid_: Hub, the tool, unity binary

**Hub CLI**
The deprecated headless command-line interface to Unity Hub. Superseded by the **Unity CLI**; no longer used on this machine.
_Avoid_: Unity CLI, hub command

**Unity Hub**
The Unity Hub desktop GUI for managing editors and projects. Removed from this machine; the **Unity CLI** is its replacement.
_Avoid_: Hub, the app, the GUI

**Pipeline package**
The Editor-side component a Unity project installs to expose its running Editor to the **Unity CLI**. It is what lets the CLI drive a live Editor — create and edit GameObjects and scenes, run C#, enter Play mode — instead of hand-editing project files.
_Avoid_: pipeline, the plugin, the bridge

**editor install**
A Unity Editor that lives under the standard editor path and is managed by the **Unity CLI** — installed, listed, and upgraded through it — as opposed to an Editor placed there by hand or by the old Hub.
_Avoid_: editor, the editor, installed editor

**Unity skill**
An agent skill from the official Unity skills collection that teaches the coding agent how to use the **Unity CLI** and drive a running Editor. It loads on demand when a Unity task matches its description.
_Avoid_: skill, the plugin, unity integration

---

Decisions are recorded in [`docs/adr/`](./docs/adr/) — including [ADR-0003](./docs/adr/0003-unity-cli-replaces-hub.md) for the Unity CLI. Registry structure is in [`docs/llm-agent/registry.md`](./docs/llm-agent/registry.md); tuning guidance (which values, and why) is in [`docs/llm-agent/tuning.md`](./docs/llm-agent/tuning.md).
