# Research: opencode config hot-reload on `opencode.json` change

## Ticket

Research ticket #91 — [`#91`](https://github.com/sarisman84/nixos-flake/issues/91)

## Goal

Determine what running opencode instances do when `~/.config/opencode/opencode.json` changes on
disk, so a web app can word its "config applied" message correctly. Three questions:

1. opencode CLI — is config read once at process start, or re-read per session / per request?
2. opencode-desktop — a long-running Electron app that forks a bundled sidecar; does it (or the
   sidecar) ever re-read config?
3. Reload surface — is there an API, event, or `opencode serve` endpoint that pushes a new model
   list into a running instance?

## Version verified

| Component | Version | How confirmed |
| --- | --- | --- |
| `opencode` CLI | **v2.2.6** | `opencode --version`; store path `…-opencode-2.2.6` |
| `opencode-desktop` | **2.2.6** | store path `…-opencode-desktop-2.2.6` |
| desktop's bundled CLI | **2.2.6** | `resources/opencode-cli.version` → `2.2.6`; executed directly → `opencode v2.2.6` |
| nixpkgs (this flake) | `opencode` 2.2.6, `opencode-desktop` 2.2.6 | `nix eval --raw nixpkgs#opencode.version` |

Upstream source was read at the **exact release tag** `v2.2.6`
(`dc2ffcf8bf26f9e669b6aa22b95f50e12be15e06`, 2026-11-06) of `github.com/anomalyco/opencode`
(the repo formerly known as `github.com/sst/opencode`).

> **Note:** the repo's unload-policy plugin documents behaviour probed against opencode
> **1.18.31**. The installed version is now **2.2.6**, a major version with a rewritten plugin
> API — see [Secondary finding](#secondary-finding-the-unload-policy-plugin-no-longer-loads).

## Findings

### 1. CLI — config is read at startup **and** re-read automatically on change

Not once-at-start. opencode v2 runs a **live filesystem watcher over the config roots**.

- `Config` (`packages/core/src/config.ts`) computes a watch plan from the discovered config
  sources and subscribes to filesystem updates (`packages/core/src/config.ts:384-399`).
- The plan includes the **global config directory** as a directory watch
  (`packages/core/src/config/watch.ts:8-41`, global dir at line 11), so `~/.config/opencode/`
  is watched. Ignore globs exclude only `node_modules`, `.git`, `.venv`, `venv`, `__pycache__`
  (`packages/util/src/fs-util.ts:261-263`) — `opencode.json` is not ignored.
- A watcher event triggers `requestReload` (`packages/core/src/config.ts:382`), debounced
  **100 ms** (`packages/core/src/config.ts:418-425`), which calls `Config.reload()`
  (`packages/core/src/config.ts:401-415`): re-discovers the sources, re-reads and re-parses every
  config file, re-reconciles the watches, and — only if the merged result actually changed —
  publishes `config.updated` on the bus (`packages/core/src/config.ts:412`).

The **provider and model catalogs are derived state**, not a separate cache:

- `config.updated` is observed by the config-provider plugin
  (`packages/core/src/config/plugin/entry-observer.ts:20-23`), which refreshes the loaded
  documents and calls `ctx.provider.reload()`
  (`packages/core/src/config/plugin/provider.ts:21-25`).
- `provider.reload()` marks the state dirty; the next read **rebuilds it from scratch** by
  re-running every registered transform (`packages/core/src/state.ts:191-213`, `269`), so the
  config documents — including a newly added model — are re-applied to the catalog.
- The rebuild publishes `provider.updated` (`packages/core/src/provider.ts:522`) and then
  `model.updated` (`packages/core/src/model.ts:271`).

**Per session / per request** the catalog is *read* from that (now-correct) derived state — it is
not re-parsed from disk per request. The disk read happens on the watcher event, not per request.

### 2. opencode-desktop — the sidecar re-reads config; the renderer never touches the file

The desktop app does **not** read `opencode.json` itself. It spawns a background service from the
bundled CLI and talks to it over HTTP:

- `packages/desktop/src/main/service/background-service.ts:63-79` spawns
  `… serve --service` (lines 69-70) and adopts/keeps a running instance.
- The service is a normal opencode server process — so it runs the same `Config` watcher as §1.
- The renderer fetches the catalog from the service (`GET /api/model`, `GET /api/provider`) and
  subscribes to `GET /api/event`. On `provider.updated` / `model.updated` it refreshes the model
  list (`packages/client/src/solid/data.ts:1352,1355`); on `config.updated` it refreshes the
  config and websearch state (`packages/client/src/solid/data.ts:1414`).
- The model's picker is a reactive view over that store
  (`packages/app/src/providers/models/select-dialog.tsx:488`, `packages/tui/src/component/dialog-model.tsx:98`).

The `config.updated` payload is published from a per-location `Config` service, so the bus attaches
the publishing location to it (`packages/core/src/bus.ts:510-526`); the observed SSE frame was
`{"type":"config.updated","location":{"directory":"…"},"data":{}}`, which satisfies the client's
`if (!event.location) return` guard.

**So yes — the desktop picks up config changes live, with no restart.**

Note also that the TUI/CLI connect to the **same shared background service** by default
(`packages/cli/src/services/server-connection.ts:51-65`; `--standalone` opts out). So there is
normally **one** server process behind every opencode client on the machine, and it is the thing
that watches the file.

### 3. Reload surface — no "push a model list" API; there is a *reload*, and an *event*

| Surface | What it does | Can it add a model? |
| --- | --- | --- |
| **Filesystem watcher** (automatic) | Re-reads config on change, publishes `config.updated` → `provider.updated` → `model.updated` | Yes — this is the normal path |
| **`config.updated` SSE event** (`GET /api/event`) | Notification that config was re-read | n/a (notification only) |
| **`POST /api/location/reload`** | Tears down and rebuilds **every loaded location**, re-reading config from disk (`packages/protocol/src/groups/location.ts:51-62`, `packages/core/src/location-service-map.ts:20-36`) | Yes — heavier; cancels pending permissions/forms, emits `location.shutdown` |
| **`PATCH /api/experimental/config`** | Writes the global config file and triggers a reload (`packages/core/src/config.ts:465-486`) | **No** — `Config.Patch` only carries `shell` (`packages/schema/src/config.ts:119-122`) |
| `opencode service restart` | Restarts the background daemon | Yes, bluntly |

There is **no endpoint that pushes a model list into a running instance**. The model list is
derived state that gets *recomputed*, not pushed.

### User-visible consequences

| | Question | Answer |
| --- | --- | --- |
| **(a)** | Does a **new session in an already-running** TUI/CLI instance see a model added to `opencode.json`? | **Yes.** Verified by probe: a session created against a server that started *before* the model existed accepted the new model id. |
| **(b)** | Is it **only newly started processes** that see it? | **No.** The running server picks it up in **~290 ms** (measured), with no restart. |
| **(c)** | Does **opencode-desktop** need a full restart? | **No.** Its sidecar hot-reloads and pushes `model.updated` over SSE; the renderer refreshes the model list. |

**Apply-message wording:** the honest message is *"applied — running instances pick it up within a
second"*, not *"restart required"*. The one caveat below can force a restart.

### Caveat that decides the apply message: the watcher watches the *directory*, not the symlink target

Our live `~/.config/opencode/opencode.json` is a **symlink** into the nix store:

```
~/.config/opencode/opencode.json
  -> /nix/store/…-home-manager-files/.config/opencode/opencode.json
    -> /nix/store/…-hm_.configopencodeopencode.json   (root-owned, mode 0600)
```

The watcher subscribes to the **containing directory** (`~/.config/opencode`), not to the file's
inode or its target. Probed consequences:

| How the file is changed | Reload fires? | Note |
| --- | --- | --- |
| **Replace the symlink** with a regular file (atomic `rename` over it) | **Yes** | But it silently **un-manages the file from Nix** — the next `nixos-rebuild` reverts it. |
| **Retarget the symlink** to a new file (the Home Manager deploy shape) | **Yes** | This is what `nixos-rebuild` does, and it works. |
| **Write through the symlink** to a target *outside* the watched directory | **No** | Watcher never sees it — model list stays stale. |
| Write through the symlink into the nix store | n/a | Impossible: the store is read-only and root-owned. |

So a web app cannot "write in place" to our live config at all; it must either replace the path or
retarget the symlink. Replacing the path works for the reload but breaks Nix management, so
**prefer retargeting, or write the file into `~/.config/opencode/` as a regular file and accept
that Nix no longer owns it.**

A second live-config subtlety: `~/.config/opencode/` also contains **`opencode.jsonc`**
(regular file, currently only `{"plugins": ["opencode-skill-creator"]}`). Both names are loaded
from the global directory, and `opencode.jsonc` is loaded **after** `opencode.json`
(`packages/core/src/config/discovery.ts:12` + `packages/core/src/config.ts:266-273`), and the
last matching document wins (`Config.latest` uses `findLast`,
`packages/core/src/config.ts:28-31`). They do not overlap today, but a web app that only rewrites
`opencode.json` must know `opencode.jsonc` is present and takes precedence for shared keys.

## Evidence

### Empirical probes (all in throwaway sandboxes; live state untouched)

Sandbox: temp `HOME` with `XDG_*` redirected, neutralised `OPENCODE_CONFIG` /
`OPENCODE_SERVER_PASSWORD` (the harness injects both), minimal `opencode.json` with a custom
provider `probe` (`npm: @ai-sdk/openai-compatible`, `baseURL: http://127.0.0.1:9/v1`) and models
`model-a`, `model-b`. Two servers were exercised: a plain `opencode serve --port …` and an
`opencode serve --service` (the exact mode the desktop daemon uses).

**Probe 1 — in-place write, plain `serve`:**

```
# baseline
curl -s "http://127.0.0.1:7791/api/model?directory=/tmp/opencode/probe/work" -u opencode:probepass
#   → probe models: ['model-a', 'model-b']
# mutate: add model-c, write in place
# SSE (curl -sN http://127.0.0.1:7791/api/event):
#   1 × "config.updated"   2 × "provider.updated"   2 × "model.updated"
# after:
#   probe models: ['model-a', 'model-b', 'model-c']
```

**Probe 2 — atomic replace (`write temp` + `os.replace`), plain `serve`:** added `model-d` →
`config.updated` fired, list became `['model-a','model-b','model-c','model-d']`.

**Probe 3 — atomic replace, `serve --service` (desktop daemon mode):** added `model-e` →
`config.updated` fired, list became `[… 'model-e']`. Registration file confirmed the daemon runs
**2.2.6**.

**Probe 4 — new session selects the new model (answers (a) directly):**

```
POST /api/session  {"model":{"providerID":"probe","id":"model-e"}, …}
→ HTTP 200
  {"id":"ses_e1c7208c4ffeRA1LGeHsOMBEoX",
   "model":{"id":"model-e","providerID":"probe","variant":"default"}, …}
```

The server had started *before* `model-e` existed.

**Probe 5 — latency:** three successive atomic replacements; the new model became visible via
`GET /api/model` after **290 ms, 290 ms, 293 ms**.

**Probe 6 — symlink cases (sandbox 2, config = symlink → target outside the watched dir):**

```
replace symlink with a regular file  → config.updated fired, model-b appeared   ✔
retarget symlink to a new target     → config.updated fired, models a,b,c,d      ✔
write target in place (through symlink)
                                      → NO config.updated, list stayed stale   ✘
```

**Probe 7 — `POST /api/location/reload`:** against the stale sandbox above →
**HTTP 204**, and the previously-missed `model-e` then appeared in `GET /api/model`.

### Source (all paths relative to `github.com/anomalyco/opencode` @ `v2.2.6`)

| Concern | File:line |
| --- | --- |
| Config load, watch plan, debounced reload, `config.updated` publish | `packages/core/src/config.ts:376-463` (reload `401-415`, publish `412`, debounce `420`) |
| Watch plan incl. global config dir | `packages/core/src/config/watch.ts:8-41` (global `11`) |
| Config file names / discovery order | `packages/core/src/config/discovery.ts:12` |
| Global dir documents load order (`json` then `jsonc`) | `packages/core/src/config.ts:266-273` |
| Last-wins merge | `packages/core/src/config.ts:28-31` (`Config.latest`) |
| `config.updated` event type | `packages/schema/src/config.ts:141` |
| Config provider plugin reloads provider catalog | `packages/core/src/config/plugin/provider.ts:21-25` |
| `config.updated` subscription | `packages/core/src/config/plugin/entry-observer.ts:20-23` |
| Derived-state rebuild on `reload()` | `packages/core/src/state.ts:191-213`, `269` |
| `provider.updated` / `model.updated` publication | `packages/core/src/provider.ts:522`; `packages/core/src/model.ts:271` |
| Watcher backend (parcel/inotify) | `packages/core/src/filesystem/watcher.ts:1-40` |
| Ignore globs | `packages/util/src/fs-util.ts:261-263` |
| `POST /api/location/reload` | `packages/protocol/src/groups/location.ts:51-62`; `packages/core/src/location-service-map.ts:20-36` |
| `PATCH /api/experimental/config` (shell only) | `packages/protocol/src/groups/config.ts:35-45`; `packages/schema/src/config.ts:119-122` |
| CLI/TUI share the background service | `packages/cli/src/services/server-connection.ts:51-65` |
| Desktop spawns `serve --service` | `packages/desktop/src/main/service/background-service.ts:63-79` |
| Desktop client refreshes on provider/model updates | `packages/client/src/solid/data.ts:1352,1355,1414` |
| TUI model list source | `packages/tui/src/component/dialog-model.tsx:98` |
| API paths probed | `packages/protocol/src/groups/model.ts` (`/api/model`), `…/provider.ts` (`/api/provider`), `…/event.ts:61` (`/api/event`) |

### Upstream tests (behavioural confirmation in-tree)

- `packages/core/test/config/reload.test.ts` — "config plugin reloads", e.g. *"loads skills when
  `${root}` appears after startup"*: writes a config file after startup and waits for
  `Config.latest(entries, "shell")` to reflect it.
- `packages/core/test/config/watch.test.ts`, `packages/core/test/config/discovery.test.ts`.

### Docs

- `https://opencode.ai/docs/config/` — the config reference. It documents file locations and
  precedence but says **nothing about hot-reload**. It does state: *"Automatic installation does
  not restart a running server. Restart it manually to activate the installed update."* — that is
  about opencode's own **binary** update, not about config.

### Secondary finding: the unload-policy plugin no longer loads

Not part of the three questions, but the ticket asks to verify our plugin's documented facts
against the installed version, and this is the headline:

- opencode 2.2.6 replaced the V1 plugin API. A plugin is now
  `{ id, effect: (ctx) => Effect<void> }` (`packages/plugin/src/effect/plugin.ts:62-65`), with
  `ctx.event.subscribe()`, `ctx.session.hook("context", …)`, `ctx.provider.transform(…)` and so on.
- **`chat.params` no longer exists anywhere in the v2 codebase** (only referenced in
  `services/site/src/docs/content/build/plugins/migrate-v1.mdx`, which maps
  `chat.params` → `ctx.session.hook("context", …)` and `event` → `ctx.event.subscribe()`).
  `packages/core/src/v1/` contains only config migration — no plugin compatibility shim.
- Our plugin (`users/spyro/modules/productivity/llm-agent/policy/plugin.ts`) returns the **V1**
  shape (`{ event, "chat.params", dispose }`), so it cannot load on 2.2.6.
- Corroboration (read-only): `~/.local/state/llm-agent/heartbeat.json` was last written
  **2026-10-20T09:47:25** — **27 days stale**. Per this repo's own convention ("a missing
  heartbeat means the plugin failed to load"), the plugin has not been running since the v2
  upgrade.

### Not verified

- The Electron desktop app was **not** launched (headless environment). Its behaviour is derived
  from the v2.2.6 source plus the fact that its sidecar is an ordinary `opencode serve --service`
  process, whose hot-reload was verified directly (Probe 3).
- Whether the *web* app's own client (the one the ticket is about) re-fetches `/api/model` after a
  `config.updated` event was not tested — that is the web app's own code, outside this repo.

## Sources

- opencode upstream (v2.2.6 tag): <https://github.com/anomalyco/opencode/tree/v2.2.6>
  (formerly <https://github.com/sst/opencode>)
- Config docs: <https://opencode.ai/docs/config/>
- Plugin v1→v2 migration guide: `services/site/src/docs/content/build/plugins/migrate-v1.mdx`
  @ `v2.2.6`
- Config JSON schema: <https://opencode.ai/config.json>
- Issue tracker entry: <https://github.com/sarisman84/nixos-flake/issues/91>

**Versions verified against:** `opencode` CLI **v2.2.6**; `opencode-desktop` **2.2.6**
(bundled CLI **2.2.6**); upstream source tag **v2.2.6** (`dc2ffcf`).
