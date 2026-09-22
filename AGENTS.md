# nixos-flake — Agent Guide

## Overview

A NixOS + Home Manager flake managing one host (`two-b`, `x86_64-linux`) and one user (`spyro`). Outputs NixOS system configurations and a shared devShell.

## Repo layout

```
flake.nix                  # flake inputs + outputs (nixosConfigurations, devShells)
flake.lock
hosts/<host>/              # NixOS host configs
  two-b/                   #   host.nix (declares spyroFlake.hosts.two-b), configuration.nix, per-concern .nix
users/<user>/              # Home Manager user configs
  spyro/
    user.nix               #   declares spyroFlake.users.spyro
    modules/               #   Home Manager modules auto-imported (general, bash, llm-agent, vscode, git, ...)
desktop-env/               # Desktop environment modules (kde-plasma, niri)
shared/library/            # Shared library
  builder.nix              #   evaluates hosts → users → nixosSystem + home-manager
  project-types.nix        #   option schemas (spyroFlake.hosts, spyroFlake.users)
  utilities.nix            #   getDirectoryNames, getNixFileNames
shared/modules/            # Shared NixOS modules (e.g. nvidia.nix)
AGENTS.md                  # this file
```

## How it evaluates

- `builder.nix` reads `hosts/*` → for each host, reads its `users/*` → builds a `lib.nixosSystem` + home-manager config.
- Each `hosts/<host>/host.nix` declares `spyroFlake.hosts.<host>` with `{ system, users, desktopEnv, permittedInsecurePackages }` (schema in `project-types.nix`).
- Each `users/<user>/user.nix` declares `spyroFlake.users.<user>` with `{ groups, home, pfp, system-modules }`.
- SpecialArgs passed to modules: `pkgs` (unstable), `pkgsStable` (26.05), `sharedImports` (from `shared/modules/`), `inputs`.
- Home Manager modules use `{ pkgs, lib, config, ... }`. NixOS modules use `{ pkgs, sharedImports, ... }`.

## Conventions

- Add a host → `hosts/<name>/` with `host.nix` (declare `spyroFlake.hosts.<name>`) + `configuration.nix` + any `.nix` modules; add the user's host to `host.nix`'s `users` list.
- Add a user module → drop a `.nix` file into `users/<user>/modules/`; it's auto-imported by `builder.nix` via `getNixFileNames`.
- `pkgs` = nixos-unstable; `pkgsStable` = nixos-26.05. `llama-cpp` (used by `llm-agent`) is intentionally pinned to stable.
- Never commit `env/*.env` (gitignored; holds API keys).

## Version Control

- Commits should be concise and use an appropriate prefix (e.g. `feat:`, `fix:`, `chore:`, `refactor:`, `docs:`).
- Always ask the user to validate your work before committing or pushing to the repo.

## Commands

### Deploy / config (bash functions — interactive shell only)

These are defined in `users/spyro/modules/productivity/bash/commands.sh` (loaded via `programs.bash.initExtra`). They only work in an interactive bash shell:

| Command | What it does |
|---|---|
| `config build two-b` | **Deploy** — `sudo nixos-rebuild switch --flake ~/config/nixos-flake/#two-b --show-trace` (needs password; sudo is run0-aliased) |
| `config update two-b` | `nix flake update` + deploy with `--upgrade` |
| `config clear` | GC + switch boot config |
| `config` | Open the flake in VSCode |
| `check` | `git status` |
| `commit -m "msg"` | `git add . && git commit -m` |
| `push` / `pull --rebase` | Git push/pull |
| `branch create|switch|list` | Branch shortcuts |
| `repo link <url>` | Add remote |

**For non-interactive / automated use** (e.g. an agent shell), call the underlying command directly:
```bash
sudo nixos-rebuild switch --flake ~/config/nixos-flake/#two-b --show-trace
```

### Verification workflow (3 tiers)

1. **`nix flake check`** — fast, read-only, no sudo. Run after *every* edit. Catches evaluation/syntax errors.
2. **`sudo nixos-rebuild build --flake .#two-b`** — dry build (no switch). Proves the system builds. Use before committing.
3. **`config build two-b`** (or the sudo equivalent) — actual deploy. Only when you want it live.

**Caveat:** `check`/`build` prove evaluation/build, not runtime correctness; a real deploy is the final test.

### DevShell

```bash
nix develop .           # enter devShell
```
Packages available: `nix`, `git`, `alejandra`, `shellcheck`.
- Format a file: `alejandra --format <file>` (repo is *not* currently alejandra-formatted — only format files you touch).
- Check formatting: `alejandra --check <file>`.
- Validate shell scripts: `shellcheck <file>`.

## Gotchas

- The `opencode` wrapper script (in `users/spyro/modules/productivity/llm-agent/opencode-wrapper.sh`) is baked into the Nix store. Rebuild (`config build two-b`) before testing changes — see `llm-agent/TESTING.md`.
- `env/*.env` files are gitignored (API keys for figma/stitch). Never commit or read secrets into flake output.
- `sudo` is actually `run0` with `enableSudoAlias` and `wheelNeedsPassword = true` — deploy commands prompt for a password and won't run unattended.
- `opencode.json` is managed via Home Manager; symlinked into `~/.config/opencode/opencode.json`.
