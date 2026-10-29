# Unity CLI replaces Unity Hub

Unity management (editor installs, modules, projects, sign-in) moves from the Unity Hub GUI to the official standalone Unity CLI (`unity` binary). The Hub package is dropped from the flake; editor installs already on disk stay and are managed by the CLI in place. IDEs (VSCode via the Unity extension, Rider) are unaffected: they talk to the Editor's scripting backend, not Hub.

## Considered options

- **Store-pinned binary via `fetchurl` (chosen).** The CLI is a single pre-built C# Native AOT binary served from Unity's CDN with a version manifest. A Nix derivation `fetchurl`s a pinned `version` + `sha256`, installs it to `$out/bin/unity`, and `patchelf`s the interpreter/RPATH to the store's glibc + libgcc (NixOS stubs `/lib64/ld-linux-x86-64.so.2`, so a bare copy cannot run). Reproducible, no deploy-time network, no activation hook.
- **Runtime bootstrap + `unity self-update` (superseded).** A home activation hook ran the official install script (`curl | bash`) only when `~/.local/bin/unity` was missing, and `self-update` kept it current. Rejected in favour of the package: it fetched at every fresh activation (a deploy-time network dependency), was not reproducible, and a hung/slow download could stall a system switch.
- **Keeping Hub alongside as a GUI fallback (rejected).** The CLI covers every Hub task in use, and two management surfaces would drift: Hub auto-updates the CLI it bundles, which would fight a flake-managed copy.

## Consequences

- The CLI is a normal Nix package in `home.packages`, so `unity` is on PATH like any other tool — no `~/.local/bin` PATH entry and no activation hook.
- **Pinned, not self-updating:** the version + `sha256` are baked into the derivation. The CLI is pre-1.0 (`1.0.0-beta.x`) and moves fast, so it will go stale; updating is a two-field bump (`version` + `sha256`, from `latest-beta.json`) plus a rebuild. This is the accepted trade-off for reproducibility and a clean deploy.
- The `patchelf` step is load-bearing: without it the binary fails to start on NixOS (stub loader). If the CLI's dynamic dependencies change, the RPATH may need adjusting.
- A fresh machine needs no bootstrap step — the CLI is built into the system on first deploy.
