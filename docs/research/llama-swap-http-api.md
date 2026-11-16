# Research: llama-swap HTTP API surface

## Ticket

Research: llama-swap HTTP API — [`#90`](https://github.com/sarisman84/nixos-flake/issues/90)

## Goal

Establish what the llama-swap HTTP API actually offers, so a web app's **apply flow** and
**status strip** are built on facts rather than guesses. Four questions: runtime model
registration, health/resident-model reporting, restart semantics, config watching.

## Version verified against

| Fact | Value | How verified |
|------|-------|--------------|
| Binary | `/nix/store/cgysxik57wpmk12q3v9b5in75zr921dj-llama-swap-268/bin/llama-swap` | `readlink -f $(which llama-swap)` |
| Version | `268` | `llama-swap --version` → `version: 268 (2576af3ac6aaec841706c212186f0475b086bb5b), built at '2026-10-28T03:25:51Z'` |
| Upstream repo | `github.com/mostlygeek/llama-swap` | confirmed; upstream `mostlygeek` owner matches our repo's existing citations in `docs/llm-agent/llama-server-shutdown.md:162` |
| Upstream commit | `2576af3ac6aaec841706c212186f0475b086bb5b` | identical to the `--version` commit string |
| Upstream tag | **`v268`** exactly | `git tag --points-at 2576af3` → `v268`; commit subject `CHANGELOG: add v268` |

Every source citation below is from that exact commit (cloned to `/tmp/opencode/llama-swap`,
checked out at `2576af3`). `v269` (next tag) adds **no** new route — `git diff v268..v269 --
internal/server/server.go` shows only a `hint` import and comment churn — so this API surface
is representative of the pinned version.

## Environment probed

Live backend on `127.0.0.1:8080`, systemd user service `llama-swap.service`, started
`2026-11-16 08:24:11 CET`. Deployed `ExecStart`:

```
llama-swap -config /home/spyro/.config/llama-swap/config.yaml -listen 127.0.0.1:8080
```

Live probes were **GET/HEAD only**. `GET /unload` and all `POST /api/models/*` routes were
deliberately **not** probed (they mutate the resident model).

---

## Findings

### 1. Runtime model registration — **no such endpoint**

There is **no** HTTP endpoint that adds, removes, or reconfigures a model. The route table is
closed and complete: `internal/server/server.go:403-486` is the only place any handler is
registered, and it contains no `POST`/`PUT`/`DELETE` route that mutates the model registry.
`GET /api/models`, `GET /api/models/status`, `GET /api/status`, `GET /api/config`,
`GET /api/health` were all probed live and all returned **404 page not found**.

This is exhaustive, not a sample: `internal/server/server.go:389` (`mux := http.NewServeMux()`)
is the **only** `http.ServeMux` in the entire binary — the sole other hit in the repo is
`cmd/fake-model/main.go:279`, a standalone test-helper binary, not llama-swap itself. The
Tailcat listener has its own entry point (`Server.ServeTailcatHTTP`,
`internal/server/server.go:499`) but it applies a capability filter and then delegates to the
**same** mux, so it exposes no extra routes.

The only model-affecting endpoints are lifecycle ones (unload / pause / resume):

| Endpoint | Semantics | Source |
|----------|-----------|--------|
| `POST /api/models/unload` | Unload **every** running local model. Synchronous — blocks until each `llama-server` child is stopped. Body ignored. Responds `200 {"msg":"ok"}` | `server.go:464` → `apigroup.go:174-179` |
| `POST /api/models/unload/{model...}` | Unload **one** named model. `404` + `{"error":{"message":"model not found"}}` if unknown, `404` + `"no local server found for requested model"` if configured but not local. Responds `200 OK` (plain text) | `server.go:465` → `apigroup.go:181-195` |
| `GET /unload` | Same as `POST /api/models/unload` (`s.local.Unload(0)`), responds `200 OK` plain text. **A GET that unloads** — a status strip must never poll it | `server.go:439` → `api.go:340-344` |
| `POST /api/models/pause` | Pause inference **and** unload every local model. Responds `{"paused":true}` | `server.go:466` → `pause.go:67-73` |
| `POST /api/models/resume` | Re-enable inference. Models load on the next request. Responds `{"paused":false}` | `server.go:467` → `pause.go:77-82` |
| `PUT /api/profiles/active` | Switch the **active profile** (routing preset over pre-declared models). Body `{"name":"<profile>"}` or `{"name":null}` to clear. Responds `{"active":"<profile>"}`. This is routing reconfiguration, **not** model registration | `server.go:469` → `apigroup.go:85-113` |

`GET /api/profiles` returns `{"active":null,"profiles":[]}` live — this deployment defines no
profiles.

**Consequence for the apply flow:** the model registry is *config-file* state, not API state.
Adding or reconfiguring a model requires editing the config source and getting llama-swap to
re-read it (see §4). There is no API-call "apply" that mutates the registry.

### 2. Health & resident model

Three distinct things, three different endpoints:

**a) llama-swap's own liveness** — `GET /health` (and the alias `GET /wol-health`) returns
`200` with the body `OK`. That is the whole handler (`internal/server/api.go:436-439`): it says
nothing about the upstream backend. Both confirmed live.

**b) Which model is resident** — `GET /running` is the endpoint for this. Response shape
(`internal/server/api.go:346-367`):

```json
{"running":[{"model":"qwen3.8-27b-200k","state":"ready","cmd":"...","proxy":"...","ttl":0,"name":"","description":""}]}
```

`state` is the process state: `stopped` | `starting` | `ready` | `stopping` | `shutdown`
(`internal/process/process.go:12-20`). Only non-stopped/non-shutdown processes appear
(`internal/router/base.go:415-427`), and the list is sorted by model id. Confirmed live —
currently exactly one entry, `qwen3.8-27b-200k`, state `ready`.

**c) Backend (llama-server) health** — there is **no** dedicated endpoint that reports the
upstream's `/health` probe result. Backend health is surfaced *indirectly* as the process
state: a model only reaches `ready` after its `checkEndpoint` (here `/health`, per the
generated `config.yaml`) passes. Two read-only views of that:

- `GET /v1/models` (alias `GET /models`) — OpenAI-compatible listing. Every model carries
  `status.value` = `"loaded"` | `"unloaded"` (`internal/server/api.go:138-160`, handler
  `handleListModels`). Confirmed live.
- `GET /api/events` — SSE stream. Each message is `event:message` with
  `data:{"type":"modelStatus","data":"<json array>"}`. The array is `apiModel`
  (`internal/server/apigroup.go:23-47`): `id`, `name`, `description`, `state`
  (`stopped`/`starting`/`ready`), `unlisted`, `peerID`, `aliases`, `capabilities`,
  `context_length`, `readySince` (RFC3339), `uptimeMs`, `loadingProgress`,
  `loadingMessage`. Confirmed live — the first `modelStatus` frame carried all 18
  models, exactly one non-stopped: `qwen3.8-27b-200k` with `state:"ready"`,
  `readySince:"2026-11-16T08:44:44Z"`, `uptimeMs:306301`. So the SSE stream **does**
  identify the resident model, and agrees with `/running`.

Other read-only diagnostics confirmed live: `GET /metrics` (Prometheus text),
`GET /api/performance` (buffered GPU/system samples), `GET /api/hardware` (startup hardware
snapshot), `GET /api/metrics/activity` (paginated request log),
`GET /api/metrics/stats` (aggregate token/request stats), `GET /logs` and `GET /logs/stream`
(log tail), `GET /api/version` (`{"version":"268","commit":"2576af3…","build_date":"…"}` —
live, matching the pinned version).

### 3. Restart semantics — **yes, full unload**

A service restart **fully unloads** the resident model. Chain, all confirmed in source:

1. `SIGINT`/`SIGTERM` → the shutdown branch (`llama-swap.go:486-531`): streams closed, HTTP
   server shut down, then `srv.Shutdown(remaining)` (`llama-swap.go:531`).
2. `Server.Shutdown` → `router.Shutdown` (`internal/server/server.go:630-667`,
   `internal/router/base.go:493-506`).
3. `baseRouter.handleShutdown` → for **every** running process, `p.Stop(stopTimeout)`
   (`internal/router/base.go:319-345`, stop at `:343`), then `StopProcesses`.
4. `ProcessCommand.Stop` (`internal/process/process_command.go:827`) → SIGTERM to the process
   group, SIGKILL after the timeout (see also `docs/llm-agent/llama-server-shutdown.md:26-33`).

Graceful-shutdown budget is `shutdownTimeout = 30 * time.Second` (`llama-swap.go:43`).

**Therefore:** after a restart the next request reloads the model from scratch (full model
load, not a resume). VRAM is freed by the stop. This matches the upstream doc statement that
"a clean llama-swap shutdown or config reload stops every loaded model" and that "backends are
unloaded, nothing is left behind"
(`docs/kb/guides/tools/kubeswap.md:168-175`).

### 4. Config watching — **SIGHUP always; file watcher only with `-watch-config`**

Both mechanisms exist, and they are **not** enabled equally in this deployment.

**SIGHUP → reload** (always active, no flag needed). `signal.Notify(sigChan, syscall.SIGINT,
syscall.SIGTERM, syscall.SIGHUP)` (`llama-swap.go:455`) and `case syscall.SIGHUP:` →
`proxyLog.Info("received SIGHUP, reloading config")` → `go reload()` (`llama-swap.go:483-486`).
So `systemctl --user kill -s HUP llama-swap` re-reads the config **without** restarting the
service.

**File watcher → opt-in.** The flag exists (`llama-swap.go:126`:
`flag.Bool("watch-config", false, "reload config on file change")`) and is only wired up
under `if *flagWatchConfig` (`llama-swap.go:420-452`). It is **poll-based, not fsnotify**:
`internal/watcher/watcher.go:17` (`DefaultInterval = 2 * time.Second`), comparing
`os.Stat` mtime + size (`:60-85`). The package doc explains it deliberately avoids inotify
because it must survive Docker bind-mounts and k8s ConfigMap symlink projections
(`internal/watcher/watcher.go:1-6`).

**This deployment does not pass `-watch-config`** — the deployed unit is
`-config …/config.yaml -listen 127.0.0.1:8080` with no watcher flag, and the flake that
generates it sets the same `ExecStart` (`users/spyro/modules/productivity/llm-agent/llama-swap.nix:326`).
**Consequence: rewriting `config.yaml` alone does nothing. A SIGHUP is required.**

Two further facts that decide the apply flow:

- **A reload also unloads the resident model.** `reload()` builds the new server, then calls
  `old.Shutdown(shutdownTimeout)` (`llama-swap.go:400`) — which runs the same
  `p.Stop()` path as §3. The upstream docs say the same ("the old server shuts down through
  the existing reload lifecycle", `docs/kb/guides/routing/groups-and-matrix.md:239-245`).
  **A config reload is therefore not a "free" apply — it evicts the resident model too.**
- **The config file is a Nix-store symlink, and the watcher's change detection is fragile
  here.** `~/.config/llama-swap/config.yaml` is a symlink into `/nix/store`
  (Home Manager owns it; `users/spyro/modules/productivity/llm-agent/llama-swap.nix:403`
  renders it). `os.Stat` follows symlinks, so the watcher sees the **store target**, whose
  mtime is Nix's normalised `1` (epoch) and whose size is the content length:

  ```
  $ stat -L -c '%n mtime=%Y size=%s' ~/.config/llama-swap/config.yaml
  /home/spyro/.config/llama-swap/config.yaml mtime=1 size=7163
  ```

  The watcher fires only when mtime **or size** differs
  (`internal/watcher/watcher.go:84`). Because every Nix store file has mtime `1`, a
  Home-Manager redeploy that changes the config **to the same byte length** would produce an
  identical snapshot and the watcher would **silently not fire**. Content-length changes (the
  normal case for adding/removing a model) do fire. → **Do not rely on the watcher; send
  SIGHUP.**

**The apply flow, therefore, is:**

1. Write the new config at its real source of truth (the flake registry:
   `users/spyro/modules/productivity/llm-agent/config.json` + `models/<key>.json`), not by
   editing the store-backed symlink (read-only).
2. Deploy it (`config build two-b` → Home Manager relinks `config.yaml`).
3. Signal the backend: `systemctl --user kill -s HUP llama-swap` — **not** a restart, so the
   process stays up (but the resident model is evicted either way, by §3).
4. Observe the result via `GET /api/version` (did the reload land?), `GET /running`
   (is anything resident?), and the `GET /api/events` SSE `modelStatus` frames.

---

## Endpoint inventory

Legend: **[P]** = confirmed by live GET/HEAD probe against `127.0.0.1:8080`;
**[S]** = confirmed in source only (route table `internal/server/server.go:403-486`);
**[U]** = upstream-only route, not relevant to this deployment.

### Meta / health / status

| Method | Path | Purpose | Status |
|--------|------|---------|--------|
| GET | `/` | Redirect to the embedded web UI (`Location: ui/`), `302` | **[P]** `302` |
| GET | `/health` | llama-swap process liveness. Body `OK`, `text/plain` | **[P]** `200 OK` |
| GET | `/wol-health` | Alias of `/health`, same handler | **[P]** `200 OK` |
| GET | `/running` | **Resident model(s)** + process state + cmd/ttl/name. `{"running":[…]}` | **[P]** `200` |
| GET | `/v1/models` | OpenAI model list; each item has `status.value` = `loaded`/`unloaded` | **[P]** `200` |
| GET | `/models` | Alias of `/v1/models` | **[P]** `200` |
| GET | `/api/events` | SSE: `event:message`, `data:{"type":…,"data":…}`. Types: `modelStatus`, `activity`, `inFlight`, `uiConfig`, `profile`, `pause` | **[P]** `200` (SSE) |
| GET | `/api/events/logs` | SSE log stream; needs ≥1 of `?proxy`/`?upstream`/`?http` | **[P]** `400` without params |
| GET | `/metrics` | Prometheus text format (`llamaswap_*` gauges) | **[P]** `200` |
| GET | `/api/performance` | Buffered GPU/system samples (`?after=<RFC3339>` filter) | **[P]** `200` |
| GET | `/api/hardware` | Hardware snapshot taken at process startup | **[P]** `200` |
| GET | `/api/version` | `{"version","commit","build_date"}` — live returned `268` / `2576af3…` | **[P]** `200` |
| GET | `/api/metrics/activity` | Paginated request/response activity rows | **[P]** `200` |
| GET | `/api/metrics/stats` | Aggregate request/token stats + histograms | **[P]** `200` |
| GET | `/api/captures/{id}` | Stored request/response capture for a metric id | **[P]** `404` for unknown id |
| GET | `/api/tailcat` | Tailcat relay address/enabled/models | **[P]** `{"address":"","enabled":false,"models":[]}` |
| GET | `/logs` | Combined log history (plain text) | **[P]** `200` |
| GET | `/logs/stream`, `/logs/stream/{id...}` | Live log tail (SSE) | **[S]** |

### Model lifecycle (mutating — **not** probed live)

| Method | Path | Purpose | Status |
|--------|------|---------|--------|
| POST | `/api/models/unload` | Unload **all** running models; sync; `{"msg":"ok"}` | **[S]** |
| POST | `/api/models/unload/{model...}` | Unload one model; `200 OK` / `404` | **[S]** |
| GET | `/unload` | **GET that unloads everything** — never poll this | **[S]** |
| POST | `/api/models/pause` | Pause inference + unload all; `{"paused":true}` | **[S]** |
| POST | `/api/models/resume` | Resume inference; `{"paused":false}` | **[S]** |

### Profiles, inflight, MCP, UI, passthrough

| Method | Path | Purpose | Status |
|--------|------|---------|--------|
| GET | `/api/profiles` | `{"active":…,"profiles":[{id,description,pins}]}` | **[P]** `200` |
| PUT | `/api/profiles/active` | Set active profile; body `{"name":"<id>"}` / `{"name":null}` | **[S]** |
| POST | `/api/inflight/{id}/cancel` | Cancel an in-flight model-dispatched request by inflight id | **[S]** |
| — | `/api/mcp` | MCP server exposing llama-swap's own docs. Registered method-agnostically; non-POST → `405` | **[P]** `HEAD` → `405` |
| GET | `/ui/` | Embedded Svelte SPA (the reference web app) | **[P]** `200` |
| GET | `/favicon.ico`, `/ui/site.webmanifest`, `/ui/web-app-manifest-*.png` | UI assets | **[S]** |
| — | `/upstream/{path...}`, `/comfyui/{path...}`, `/audiocpp/{path...}` | Passthrough to upstream servers | **[S]** |
| POST/GET | `/v1/chat/completions`, `/v1/responses`, `/v1/completions`, `/v1/messages`, `/v1/messages/count_tokens`, `/v1/embeddings`, `/reranking`, `/rerank`, `/v1/rerank`, `/v1/reranking`, `/infill`, `/completion`, `/v1/audio/speech`, `/v1/audio/voices`, `/v1/images/generations`, `/v1/images/edits`, `/v1/audio/transcriptions`, `/sdapi/v1/txt2img`, `/sdapi/v1/img2img`, `/sdapi/v1/loras`, `/props`, `/audioapi/v1/tasks/run`, `/v1/systemone`, and the versionless `/v/…` aliases | Model-dispatched routes — the `model` field selects and (re)loads the backend | **[S]** (`server.go:138-185`) |

### Probed and confirmed **absent** (404)

`/api`, `/api/models`, `/api/models/status`, `/api/models/unloaded`, `/api/status`,
`/api/health`, `/api/healthz`, `/api/config`, `/api/metrics`, `/api/requests`, `/api/logs`,
`/api/swaps`, `/api/groups`, `/api/routing`, `/api/info`, `/api/ping`, `/api/inflight`,
`/v1/health`, `/readyz`, `/docs`, `/api/events/health`.

All of these returned `404 page not found` — the mux has no such pattern. Note in particular
that **`/api/models` does not exist**: `POST /api/models/unload` is a literal path, not a
collection endpoint.

There is **no OpenAPI/Swagger document** in the repo (`find -iname '*openapi*' -o -iname
'*swagger*'` → empty); the route table in `internal/server/server.go` is the only
authoritative list.

---

## Sources

### Primary — upstream source at the exact pinned commit

`github.com/mostlygeek/llama-swap` @ `2576af3ac6aaec841706c212186f0475b086bb5b` (tag `v268`),
cloned to `/tmp/opencode/llama-swap` for reading.

- `llama-swap.go:43` — `shutdownTimeout = 30 * time.Second`
- `llama-swap.go:126` — `-watch-config` flag definition
- `llama-swap.go:327-414` — `reload()`; `:400` `old.Shutdown(shutdownTimeout)`
- `llama-swap.go:420-452` — watcher setup, gated on `-watch-config`
- `llama-swap.go:455`, `:483-486` — `SIGHUP` → `reload()`
- `llama-swap.go:486-531` — `SIGINT`/`SIGTERM` shutdown path; `:531` `srv.Shutdown(remaining)`
- `internal/server/server.go:138-185` — model-dispatched route lists
- `internal/server/server.go:389` — the **only** `http.ServeMux` in the binary
- `internal/server/server.go:403-486` — **the complete route table**
- `internal/server/api.go:138-160` — `handleListModels` (`status.value` = loaded/unloaded)
- `internal/server/api.go:340-344` — `handleUnload` (`GET /unload`)
- `internal/server/api.go:346-367` — `handleRunning` (`GET /running`)
- `internal/server/api.go:425-433` — `handleMetrics` (`GET /metrics`)
- `internal/server/api.go:436-439` — `handleHealth` (`GET /health`)
- `internal/server/apigroup.go:23-47` — `apiModel` struct (SSE `modelStatus` shape)
- `internal/server/apigroup.go:62-83` — `handleAPIProfiles`
- `internal/server/apigroup.go:85-113` — `handleAPIActiveProfile`
- `internal/server/apigroup.go:112-160` — `modelStatus()` (state resolution)
- `internal/server/apigroup.go:174-195` — `handleAPIUnloadAll` / `handleAPIUnloadModel`
- `internal/server/apigroup.go:388-397` — `handleAPIVersion`
- `internal/server/apigroup.go:496-497` — `handleAPICancelInflight`
- `internal/server/apigroup.go:611-679` — `handleAPIEvents` (SSE envelope + event types)
- `internal/server/pause.go:63-82` — `handleAPIPause` / `handleAPIResume`
- `internal/router/base.go:319-345` — `handleShutdown` → `p.Stop(stopTimeout)` per process
- `internal/router/base.go:407-427` — `RunningModels` / `RunningStatus`
- `internal/router/base.go:493-506` — `baseRouter.Shutdown`
- `internal/process/process.go:12-20` — process states (`stopped`/`starting`/`ready`/`stopping`/`shutdown`)
- `internal/process/process_command.go:827-838` — `ProcessCommand.Stop`
- `internal/watcher/watcher.go:1-85` — poll-based config watcher (2 s interval, mtime+size)
- `ui/src/stores/api.ts:411-455` — the reference UI's own calls (`/api/models/unload`,
  `/api/models/{pause,resume}`, `/api/models/unload/{model}`) — confirms there is no
  model-mutation call in the shipped UI either

### Primary — upstream docs at `v268`

- `docs/kb/guides/tools/kubeswap.md:168-175` — "a clean llama-swap shutdown or config reload
  stops every loaded model … backends are unloaded, nothing is left behind"
- `docs/kb/guides/routing/groups-and-matrix.md:239-245` — reload lifecycle: "the old server
  shuts down through the existing reload lifecycle"
- `docs/kb/guides/model-runtime/ttl-and-unloading.md` — `unloadTimeout` default, pause semantics
- `docs/kb/guides/operations/tailcat.md:99` — "Configuration reloads (`-watch-config` or
  `SIGHUP`) apply changes"
- `docs/kb/guides/api-integration/mcp-endpoint.md` — `/api/mcp`
- `README.md:45` — "llama-swap API" feature bullet

### Primary — this deployment

- `~/.config/systemd/user/llama-swap.service` — deployed unit (no `-watch-config`)
- `users/spyro/modules/productivity/llm-agent/llama-swap.nix:326` — generated `ExecStart`
- `users/spyro/modules/productivity/llm-agent/llama-swap.nix:403` — `config.yaml` rendered
  into the Nix store (read-only symlink)
- `users/spyro/modules/productivity/llm-agent/config.json` + `models/<key>.json` — the real
  registry source of truth for an apply flow
- `docs/llm-agent/llama-server-shutdown.md` — prior research on the unload path (same
  upstream, `main`; re-verified here against `v268`)
