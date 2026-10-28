# Unity CLI replaces Unity Hub

Unity management (editor installs, modules, projects, sign-in) moves from the Unity Hub GUI to the official standalone Unity CLI (`unity` binary). The Hub package is dropped from the flake; editor installs already on disk stay and are managed by the CLI in place. IDEs (VSCode via the Unity extension, Rider) are unaffected: they talk to the Editor's scripting backend, not Hub.

## Considered options

- **Store-pinned binary via `fetchurl` (rejected).** Reproducible, but the CLI ships frequently and the official skill warns an outdated CLI fails in ways that read like the docs being wrong. A pinned binary also defeats `unity self-update`, and IDE support depends on a recent release (`1.0.0-beta.9` fixed `unity open` breaking Rider/VS Code debugger process detection).
- **Keeping Hub alongside as a GUI fallback (rejected).** The CLI covers every Hub task in use, and two management surfaces would drift: Hub auto-updates the CLI it bundles, which would fight a flake-managed copy.

## Consequences

- The flake guarantees *presence*, Unity guarantees *currency*: a home activation hook runs the official install script only when `~/.local/bin/unity` is missing, and `unity self-update` keeps the binary current outside the Nix store.
- The binary lives in `~/.local/bin` (outside the store), so it survives GC and reboots but is not reproducible from the flake alone; a fresh machine needs one deploy to bootstrap it.
- `~/.local/bin` is not on PATH by default on this system, so the module adds it via `home.sessionVariables`.
- The hook warns rather than fails the deploy on install failure; the next activation retries.
