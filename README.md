# nixos-flake

[![NixOS](https://img.shields.io/badge/NixOS-flake-6f79c1?style=for-the-badge&logo=nixos&logoColor=white)](https://nixos.org/)
[![Home Manager](https://img.shields.io/badge/Home%20Manager-included-92845c?style=for-the-badge&logo=home-assistant&logoColor=white)](https://github.com/nix-community/home-manager)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](./LICENSE)
[![GitHub last commit](https://img.shields.io/github/last-commit/sarisman84/nixos-flake?style=for-the-badge)](./)
[![NixOS channel](https://img.shields.io/badge/nixpkgs-nixos--unstable-4479c1?style=for-the-badge)](https://github.com/NixOS/nixpkgs/tree/nixos-unstable)

A [Nix](https://nixos.org/) flake for declaratively managing one or more [NixOS](https://nixos.org/) hosts and the users on them. System configuration, Home Manager user configs, and desktop environments all live in a single, version-controlled flake — evaluated by a small shared library that turns a directory of host and user definitions into full `nixosSystem` builds.

Currently manages the `two-b` host (`x86_64-linux`, KDE Plasma) and the `spyro` user.

## Table of Contents

- [Repository layout](#repository-layout)
- [How it works](#how-it-works)
- [Installation](#installation)
  - [NixOS](#nixos)
  - [Nix (non-NixOS systems)](#nix-non-nixos-systems)
- [Development](#development)
- [Adding a host](#adding-a-host)
- [Adding a user module](#adding-a-user-module)
- [License](#license)

## Repository layout

```
flake.nix                  # flake inputs + outputs (nixosConfigurations, devShells)
flake.lock
hosts/<host>/              # NixOS host configs
  two-b/                   #   host.nix (declares the host) + per-concern .nix modules
users/<user>/              # Home Manager user configs
  spyro/
    user.nix               #   declares the user
    modules/               #   Home Manager modules, auto-imported
    system/                #   NixOS modules this user applies to hosts
desktop-env/               # Desktop environment modules (kde-plasma, niri)
shared/library/            # Shared library that assembles systems from hosts/ + users/
shared/modules/            # Shared NixOS modules applied to every host
```

## How it works

- `shared/library/builder.nix` reads every entry in `hosts/*`. For each host it reads the host's `host.nix` (which declares `spyroFlake.hosts.<host>` with `{ system, users, desktopEnv, permittedInsecurePackages }`) and the `users/*` it lists.
- Each `users/<user>/user.nix` declares `spyroFlake.users.<user>` with `{ groups, home, pfp, system-modules }`.
- The builder combines all of that into a `lib.nixosSystem` per host, with Home Manager wired in for each user.
- Special args passed to modules: `pkgs` (nixos-unstable), `pkgsStable` (nixos-26.05), `sharedImports` (from `shared/modules/`), and `inputs`.

Option schemas live in `shared/library/project-types.nix`; helpers in `shared/library/hosts.nix`, `users.nix`, `pkgs.nix`, and `utilities.nix`.

## Installation

### NixOS

This flake is a set of NixOS system configurations. Deploy a host with:

```bash
sudo nixos-rebuild switch --flake github:sarisman84/nixos-flake#two-b --show-trace
```

or, from a local clone:

```bash
sudo nixos-rebuild switch --flake ~/config/nixos-flake/#two-b --show-trace
```

Update the flake inputs and deploy in one step:

```bash
sudo nixos-rebuild switch --flake ~/config/nixos-flake/#two-b --upgrade --show-trace
```

### Nix (non-NixOS systems)

On a non-NixOS system with [Nix](https://nixos.org/download) (multi-user or single-user) installed, you can still use the flake's devShell:

```bash
nix develop github:sarisman84/nixos-flake
```

The devShell provides `nix`, `git`, `alejandra` (formatter), and `shellcheck`.

> **Note:** The `nixosConfigurations` outputs are NixOS-specific and cannot be applied on a non-NixOS system. For pure Home Manager usage, use the [home-manager flake](https://github.com/nix-community/home-manager) pattern directly against `users/<user>/modules/`.

## Development

Enter the devShell:

```bash
nix develop .
```

Verify your changes (fastest first):

1. `nix flake check` — catches evaluation/syntax errors, no sudo needed.
2. `sudo nixos-rebuild build --flake .#two-b` — dry build (no switch).
3. `sudo nixos-rebuild switch --flake .#two-b --show-trace` — actual deploy.

Format Nix files with `alejandra --format <file>`; check shell scripts with `shellcheck <file>`.

## Adding a host

1. Create `hosts/<name>/` containing a `host.nix` that declares the host:

   ```nix
   { ... }:
   {
     spyroFlake.hosts.<name> = {
       system = "x86_64-linux";
       desktopEnv = "kde-plasma";
       users = [ "spyro" ];
     };
   }
   ```

2. Add a `configuration.nix` and any per-concern `.nix` modules in the same directory.
3. Run `nix flake check`, then deploy with the `nixos-rebuild` command above.

## Adding a user module

User modules are Home Manager modules loaded per user. The builder imports the user's `modules/` **directory**, which resolves to `modules/default.nix`; that file's `imports` list is what actually pulls each module in. So a new module must be both created **and** referenced in the right `default.nix`.

The current structure:

```
users/<user>/modules/
  default.nix            # imports the top-level modules below
  general.nix
  browser.nix
  communication.nix
  flatpak.nix
  entertainment/         # subcategory — has its own default.nix
    default.nix
  productivity/          # subcategory — has its own default.nix
    default.nix
    git.nix
    vscode/
    ...
```

To add a module:

1. **Create the file** in the appropriate place:
   - Top-level concern → `users/<user>/modules/<name>.nix`
   - Belongs under an existing category (e.g. `productivity/`) → `users/<user>/modules/<category>/<name>.nix`
   - New category → create `users/<user>/modules/<category>/default.nix` and put modules inside it.

2. **Reference it** in the `imports` list of the enclosing `default.nix`:
   - Top-level file → add `./<name>.nix` to `users/<user>/modules/default.nix`
   - File inside a category → add `./<name>.nix` to that category's `default.nix` (e.g. `users/<user>/modules/productivity/default.nix`)
   - A new category directory → add `./<category>` to `users/<user>/modules/default.nix`

3. **Write the module** as a Home Manager module:

   ```nix
   { pkgs, ... }:
   {
     home.packages = with pkgs; [
       # ...
     ];
   }
   ```

4. Run `nix flake check`, then deploy with the `nixos-rebuild` command above.

> A file that is created but not added to a `default.nix` `imports` list is silently ignored — the builder only follows the `default.nix` chain.

## License

This project is licensed under the [MIT License](./LICENSE).
