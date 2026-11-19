# Penpot bundle via digest-pinned Docker extraction

Penpot (self-hosted design tool) has no Nix packaging anywhere public — nixpkgs carries only the unofficial `penpot-desktop` Electron client — and it ships **no prebuilt binaries outside Docker**: GitHub releases carry no assets, and the build bundles land in a private S3. We want a local-flake package that runs the stack as a supervised user service ("functions like an application"), so the derivation obtains its binaries by **extracting the prebuilt artifacts from the official Docker images** (`penpotapp/frontend`, `/backend`, `/exporter`, `/mcp`), pinned by image digest.

## Considered options

- **Digest-pinned Docker layer extraction (chosen).** A fixed-output derivation fetches token → manifest → layer tarballs from `registry-1.docker.io` over plain HTTPS, then unpacks the backend fat jar + its jlinked JRE, the frontend statics + nginx config template, the exporter bundle + its Chromium build, and the mcp bundle. Fast to build, exactly what the official images ship, reproducible by digest, and isolated in one derivation so the service layer never changes if the source of the binaries does.
- **From-source build (rejected for now).** Backend is Clojure/tools.deps (JDK 17+, one git dep); frontend is pnpm 12 + shadow-cljs + a WASM module; exporter is pnpm + Playwright. Proper nixpkgs style, but long first builds and a fiddly frontend toolchain. A previous nixpkgs attempt (backend only, by `hoh`) was deleted and never merged. Revisit if/when upstreaming to nixpkgs, which requires a source build.
- **Wrapping the Docker images in a container runtime (rejected).** Adds a container runtime dependency, and the user-service "application" model wants native child processes under one supervisor, not containers.

## Consequences

- **Build-time network dependency** on Docker Hub: the first build downloads the image layers (fixed-output, cached afterwards). A registry outage blocks a fresh build, not a rebuild from cache.
- **amd64 only** (host is `x86_64-linux`); the manifest fetch pins the amd64 image digest.
- **Pinned to 2.18.6.** 2.19+ makes the admin-console mandatory, and its source is **not public** (no repo, no Dockerfile in `penpot/penpot`), so a native build cannot include it. We stay on 2.18.x, where it is optional.
- **The JRE is extracted from the backend image, not taken from nixpkgs:** the official run script uses JDK 24+/26-only JVM flags (`--sun-misc-unsafe-memory-access=allow`, `--enable-preview`), so a nixpkgs JDK 21 would fail to boot the jar.
- Upstreaming to nixpkgs later means replacing the extraction derivation with a source build; the service layer (user unit, launcher, data layout) is unaffected.
