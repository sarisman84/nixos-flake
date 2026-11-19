# Penpot package — design & implementation plan

Status: **designed and confirmed with the user (2026-11-06); not yet implemented.**
Facts: [research.md](./research.md) · Decision record: [ADR-0004](../adr/0004-penpot-bundle-via-docker-extraction.md) · Vocabulary: `CONTEXT.md` → *Penpot*.

## Goal

Package the penpot server (v2.18.6) in this flake so it **functions like an application** on KDE Plasma: a desktop shortcut that brings up the whole stack on demand and opens the browser — OpenChamber-style, but for a self-hosted web app.

## Settled decisions

| # | Decision | Choice |
|---|---|---|
| 1 | Package scope | Local flake, nixpkgs-style, upstreamable later |
| 2 | Service model | systemd **user** services |
| 3 | Unit structure | **One** `penpot.service` with a supervisor script |
| 4 | Build strategy | **Digest-pinned extraction** from official Docker images (ADR-0004) |
| 5 | v1 scope | Core + exporter + mcp; pin **2.18.6**; no admin-console |
| 6 | Shortcut | **Launch-and-open** (start unit → wait for `:9001` → open browser) |
| 7 | Repo location | `packages/penpot/` + `users/spyro/modules/penpot.nix` |
| 8 | Ports | Official: 9001 / 6060 / 6061 / 4401 / 4402 / 5432 / 6379 |
| 9 | Start policy | **On-demand only** (no `WantedBy=default.target`) |
| 10 | Data stores | `postgresql_15` + `valkey` (matches the official compose) |

## Implementation details (agreed)

- **Extraction mechanics:** fixed-output derivation, amd64 only. Fetch token → manifest → layer tarballs from `registry-1.docker.io` over plain HTTPS; pin by **image digest** (tag recorded for humans). Unpack per component:
  - backend: `penpot.jar` + the **jlinked Zulu JDK 26 JRE** (the run script uses JDK 24+/26-only flags — a nixpkgs JDK 21 would not boot the jar) + `log4j2.xml` + `builtin-templates/`.
  - frontend: statics + `nginx.conf.template` (+ overrides, `csp-script-hashes.txt`). Served by **nixpkgs nginx**, template rendered with `envsubst`.
  - exporter: Node bundle + **Chromium extracted from the image** (`PLAYWRIGHT_BROWSERS_PATH`) + nixpkgs fonts (noto-color-emoji, liberation, wqy-zenhei, …).
  - mcp: Node bundle + nixpkgs `nodejs_24`.
- **Data:** `~/.local/state/penpot/` → `postgres/`, `redis/`, `assets/`, `logs/`, `secret.key`. `PENPOT_SECRET_KEY` and the postgres password are **auto-generated on first launch**, persisted mode 600 — never in the flake or the Nix store.
- **Postgres:** `initdb` on first launch; DB/user `penpot`; bound to `127.0.0.1:5432` only. Valkey on `127.0.0.1:6379`.
- **Telemetry:** disabled.
- **Crash policy:** any child dies → supervisor exits → systemd `Restart=on-failure` restarts the whole stack (postgres data is durable, so full restarts are safe).
- **Launcher:** ships in the package (`$out/bin/penpot-launch`): `systemctl --user start penpot` (idempotent), poll `http://127.0.0.1:9001` until it answers (generous timeout — first launch runs DB migrations), then `xdg-open`.
- **`.desktop` entry:** "Penpot", icon extracted from the frontend statics, `Terminal=false`, Exec = launcher.
- **Overlay:** `shared/library/pkgs.nix` extends the `unstable` set with `packages/penpot/overlay.nix`; the Home Manager module references `pkgs.penpot`.

## File layout (to create)

```
packages/penpot/
  default.nix          # per-component extraction derivations + meta `penpot` package
  overlay.nix          # adds penpot* to the pkgs set
  launcher.sh.in       # launch-and-open script (substituted at build time)
  penpot.service.in    # user unit template (supervisor ExecStart)
  supervisor.sh.in     # spawns postgres → valkey → backend → nginx → exporter → mcp
users/spyro/modules/penpot.nix   # Home Manager: user service + .desktop entry + state dir
shared/library/pkgs.nix          # (edit) extend unstable with the overlay
```

## Implementation steps

- [ ] 1. **Probe the registry** (scratch FOD or shell): resolve the `2.18.6` manifests for `penpotapp/{frontend,backend,exporter,mcp}`, record the amd64 image digests + layer digests/sizes.
- [ ] 2. **Extraction derivations** in `packages/penpot/default.nix`: one FOD per image (token → manifest → blobs, fixed-output), unpacking to per-component outputs; meta `penpot` package assembling bundle + supervisor + launcher + `.desktop` icon.
- [ ] 3. **Supervisor + unit templates**: ordered child startup with per-child log files under `~/.local/state/penpot/logs/`; first-launch init (initdb, secret generation); trap-based teardown.
- [ ] 4. **Home Manager module** `users/spyro/modules/penpot.nix`: `services.userServices.penpot` (on-demand, `Restart=on-failure`), `xdg.desktopEntries.penpot`, state dir creation.
- [ ] 5. **Overlay hook** in `shared/library/pkgs.nix`.
- [ ] 6. **Verify:** `nix flake check` → `nix build` the package (first run downloads layers) → deploy → click the shortcut → penpot loads in the browser → create a file, log out, log in, click again (data persists) → `systemctl --user stop penpot` (clean teardown).

## Known limitations (accepted)

- **2.19+ is blocked natively:** the admin-console's source is not public; we stay on 2.18.x (where it is optional) until that changes.
- First extraction build needs Docker Hub reachable (fixed-output; cached afterwards).
- Logging out stops the stack (user services); data persists, next launcher click restarts it.
- First launch is slow (backend DB migrations); the launcher waits patiently.
- amd64 only.
