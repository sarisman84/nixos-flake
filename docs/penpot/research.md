# Penpot — research findings

Facts gathered 2026-11-06 while designing the penpot package. All version numbers and ports verified against the sources linked. See [plan.md](./plan.md) for what we decided to do with them.

## Distribution status

- **Current stable: 2.18.6** (GitHub release, 2026-11-04). 2.19 is in development; its docs already describe "Upgrade to 2.19" with the admin console enabled by default.
- **Penpot server is NOT in nixpkgs.** Only the unofficial `penpot-desktop` Electron client is (`pkgs/by-name/pe/penpot-desktop/package.nix`, v0.23.2, [PR #377064](https://github.com/NixOS/nixpkgs/pull/377064)). The package request [issue #232266](https://github.com/NixOS/nixpkgs/issues/232266) was closed 2025-09-02 (nixpkgs no longer takes package requests via issues).
- **No community overlay** packages the server (checked nix-community/overlays).
- **A previous packaging attempt exists but is gone:** maintainer `hoh` packaged the backend in a fork commit (2025-11-28, "First tests look positive" in the issue thread); the commit and branch no longer resolve.
- **GitHub releases carry no prebuilt binaries** — `releases/latest` has `assets: []`, only source tarballs.
- **The only public distribution is Docker images**, namespace `penpotapp` (not `penpot`): `frontend`, `backend`, `exporter`, `mcp`, `admin-console` (+ `imagemagick`, `devenv`, `storybook`, `media-processor`). Tags: `latest`, `2.18`, `2.18.0`…`2.18.6`, `main`; multi-arch amd64+arm64.
- **Bundles are built in CI** (`./manage.sh build-bundle` inside the `penpotapp/devenv` image → zipped → **private S3** → extracted per image by `build-docker.yml`). No public non-Docker access to the jar/statics.

## Official self-hosted stack (v2.18)

Canonical source: [`docker/images/docker-compose.yaml`](https://raw.githubusercontent.com/penpot/penpot/develop/docker/images/docker-compose.yaml) on `develop`. Docs: [help.penpot.app/technical-guide](https://help.penpot.app/technical-guide/) (configuration: [configuration](https://help.penpot.app/technical-guide/configuration/)).

| Service | Image | Ports (host→container) | What it is |
|---|---|---|---|
| `penpot-frontend` | `penpotapp/frontend:2.18` | 9001 → 8080 (8082 = stub_status health) | nginx serving prebuilt statics, proxies `/api` to backend |
| `penpot-backend` | `penpotapp/backend:2.18` | 6060 | Clojure HTTP server (the app logic + DB migrations) |
| `penpot-exporter` | `penpotapp/exporter:2.18` | 6061 | Node + Playwright (design export to PNG/PDF/SVG) |
| `penpot-mcp` | `penpotapp/mcp:2.18` | 4401 (HTTP), 4402 (WS) | AI tooling bridge, plain Node |
| `penpot-admin-console` | `penpotapp/admin-console:2.18` | 3000 | **New in 2.18, optional; mandatory/default in 2.19. Source NOT public** (no repo, no Dockerfile in `penpot/penpot`) |
| `penpot-postgres` | `postgres:15` | 5432 | `POSTGRES_DB/USER/PASSWORD=penpot` |
| `penpot-valkey` | `valkey/valkey:8.1` | 6379 | `maxmemory 128mb` |
| `penpot-mailpit` | `axllent/mailpit:v1` | 1025 (SMTP), 8025 (web) | dev mail catcher (optional) |

**Key env vars** (full reference in the docs link above): `PENPOT_PUBLIC_URI` (default `http://localhost:9001`), `PENPOT_SECRET_KEY` (512-bit base64 master key), `PENPOT_DATABASE_URI` / `_USERNAME` / `_PASSWORD`, `PENPOT_REDIS_URI`, `PENPOT_INTERNAL_URI`, `PENPOT_BACKEND_URI` (default `http://penpot-backend:6060`), `PENPOT_EXPORTER_URI` (default `http://penpot-exporter:6061`), `PENPOT_MCP_URI` / `_WS`, `PENPOT_OBJECTS_STORAGE_BACKEND=fs` + `PENPOT_OBJECTS_STORAGE_FS_DIRECTORY=/opt/data/assets`, `PENPOT_TELEMETRY_ENABLED`, `PENPOT_SMTP_*`, `PENPOT_HTTP_SERVER_MAX_BODY_SIZE=367001600`, `PENPOT_FLAGS` (space-separated feature flags).

**Minimum versions:** PostgreSQL "highly recommend >= 15" (compose pins 15). Redis/Valkey: no documented minimum (compose pins valkey 8.1).

## Image contents (from `docker/images/Dockerfile.*` on `develop`)

- **backend** — Debian 13 base + **jlinked Zulu JDK 26.0.2.1 JRE** + ImageMagick 7.1.2-32 + bundle at `/opt/penpot/backend/`: single fat jar `penpot.jar`, `run.sh`, `manage.py`, `log4j2.xml`, `builtin-templates/`, `version.txt`. Run: `java $JAVA_OPTS -jar penpot.jar -m app.main` with `--enable-preview --sun-misc-unsafe-memory-access=allow --enable-native-access=ALL-UNNAMED --add-opens=java.base/java.nio=ALL-UNNAMED` (from `scripts/run.template.sh`).
- **frontend** — nginx 1.31.8 + prebuilt statics at `/var/www/app/` + `nginx.conf.template` rendered by `/entrypoint.sh` (envsubst) + `/etc/nginx/overrides/{main,http,server,assets,location}.d/` + `csp-script-hashes.txt`.
- **exporter** — Node 24.22.2 + Playwright (`PLAYWRIGHT_BROWSERS_PATH=/opt/penpot/browsers`) + xvfb + fonts (`noto-color-emoji`, `unifont`, `cyrillic`, `liberation`, `ipafont`, `wqy-zenhei`, `tlwg-loma-otf`, `freefont`) + poppler; `CMD node app.js`.
- **mcp** — Node 24.22.2; `CMD node index.js --multi-user`.

## Source build feasibility (if extraction is ever replaced)

- **Backend:** Clojure 1.12.6 + tools.deps; `clojure -T:build jar` (tools.build 0.10.14) → uberjar. One git dep (`funcool/yetti` v11.11). Key deps: next.jdbc, reitit-core, lettuce 7.8.0, postgresql 42.7.13, HikariCP, AWS SDK s3/sts, lbug + arrow. `dev/java` compiled with `javac -source/-target 17`.
- **Frontend:** ClojureScript via **shadow-cljs** + **pnpm 12.16.1** monorepo (React 19.3.0, vite 8, sass, playwright 1.63.0, storybook 10.6.1); build also compiles **render-wasm** (WASM), the mcp plugin, plugins, and `packages/ui`.
- **Exporter:** hybrid ClojureScript (shadow-cljs) + Node runtime with Playwright 1.63.0 + ioredis; its `./setup` script is *generated* by `exporter/scripts/build` (heredoc), not a repo file.
- Everything is SHA-pinned upstream (pnpm tarball, JDK, ImageMagick), so a native derivation would be reproducible — just heavy.

## Runtime requirements

- Frontend default port **9001**; assets dir `/opt/data/assets` for the `fs` storage backend.
- Backend needs **ImageMagick** (thumbnails, MIME detection, dimensions) + a `policy.xml`; fontconfig/fontforge/woff-tools/woff2 in the image.
- Exporter needs headless Chromium (Playwright) + xvfb + the font set above.
- **Air-gapped mode:** by default penpot proxies to GitHub (libraries/templates) and Google Fonts; disable via the `enable-air-gapped-conf` flag.
- Frontend/backend/exporter/mcp are all **stateless and replicable** (only postgres + assets hold state).
