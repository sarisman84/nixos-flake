---
name: create-readme
description: Creates a modern, well-structured README.md for a project. Use when the user asks to write, generate, or create a README for a repository. Produces a README with badges, table of contents, installation guide, and license reference matching the nixos-flake README style.
---

# Create README

Generate a `README.md` for the current project. The goal is a clean, modern, scannable README in the same style as `nixos-flake/README.md`.

## Workflow

1. **Inspect the project first.** Before writing anything, understand what the project is:
   - Read `flake.nix` (if present) to identify outputs, inputs, and what the project produces.
   - List the top-level directory to understand the layout.
   - Read the main config/manifest files (`package.json`, `Cargo.toml`, `pyproject.toml`, `flake.nix`, `Makefile`, etc.).
   - Read the license file to confirm the license name.
   - Read `AGENTS.md` (if present) for conventions and commands.
   - Check `git remote -v` for the GitHub `owner/repo` to use in badges.

2. **Determine the project type.** This drives the installation section:
   - NixOS flake → `nixos-rebuild` commands.
   - Nix flake (non-NixOS) → `nix develop` / `nix run` / `nix build`.
   - Node.js → `npm install` / `npm run`.
   - Rust → `cargo build` / `cargo run`.
   - Python → `pip install` / `uv` / `poetry`.
   - Other → infer from the manifest.

3. **Write the README** using the structure below.

## README Structure

### 1. Title

```markdown
# <project-name>
```

Use the repo name or a short product name. No preamble before the title.

### 2. Badges

A single line of `style=for-the-badge` shields.io badges. Include:

- **Primary tech badge** — the main language/platform (e.g. NixOS, Node, Rust, Python). Use the platform's logo.
- **Key dependency badge** (optional) — a major input or framework (e.g. Home Manager, React, Deno).
- **License badge** — `![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)` linking to the license file.
- **Last commit badge** (optional) — `![GitHub last commit](https://img.shields.io/github/last-commit/<owner>/<repo>?style=for-the-badge)`.
- **Channel/version badge** (optional) — e.g. `nixpkgs-nixos-unstable`, `npm version`, `crates.io version`.

Badge format reference (all use `?style=for-the-badge`):

```markdown
[![NixOS](https://img.shields.io/badge/NixOS-flake-6f79c1?style=for-the-badge&logo=nixos&logoColor=white)](https://nixos.org/)
[![Home Manager](https://img.shields.io/badge/Home%20Manager-included-92845c?style=for-the-badge&logo=home-assistant&logoColor=white)](https://github.com/nix-community/home-manager)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](./LICENSE)
[![GitHub last commit](https://img.shields.io/github/last-commit/<owner>/<repo>?style=for-the-badge)](./)
```

Color palette (hex, `style=for-the-badge`):

| Color | Hex | Use for |
|---|---|---|
| NixOS blue | `6f79c1` | Nix/NixOS |
| NixOS light blue | `4479c1` | nixpkgs channel |
| Gold | `92845c` | Home Manager, secondary frameworks |
| Yellow | `yellow.svg` | License (MIT) |
| Green | `2ea44f` | CI passing, stable |
| Orange | `ff69b4` or `e05d44` | WIP, beta |

### 3. Introduction

One or two sentences describing what the project is and does. Write for someone who has never seen it. Mention the primary platform, the main capability, and (for Nix projects) what it manages. Avoid marketing fluff.

Example (NixOS flake):

> A [Nix](https://nixos.org/) flake for declaratively managing one or more [NixOS](https://nixos.org/) hosts and the users on them. System configuration, Home Manager user configs, and desktop environments all live in a single, version-controlled flake.

### 4. Table of Contents

**Include a TOC only when the README has 3 or more top-level sections beyond Installation.** Format:

```markdown
## Table of Contents

- [Repository layout](#repository-layout)
- [How it works](#how-it-works)
- [Installation](#installation)
  - [NixOS](#nixos)
  - [Nix (non-NixOS systems)](#nix-non-nixos-systems)
- [Development](#development)
- [License](#license)
```

Use lowercase, hyphenated anchors matching GitHub's anchor generation. Indent subsections with 2 spaces.

### 5. Repository Layout (for Nix/multi-file projects)

A fenced code block showing the top-level directory tree, one line per entry, with inline comments:

```
flake.nix                  # flake inputs + outputs
hosts/                     # NixOS host configs
users/                     # Home Manager user configs
shared/                    # Shared library and modules
```

Align the `#` comments. Keep it to the top 2 levels only.

### 6. How It Works (optional, for non-trivial projects)

A short bulleted list explaining the architecture or data flow. 3-5 bullets max. Reference specific files by path.

### 7. Installation

Use `##` for the section, `###` per platform/variant. Always provide a fenced bash block with a runnable command.

**NixOS:**

```markdown
### NixOS

Deploy a host:

```bash
sudo nixos-rebuild switch --flake github:<owner>/<repo>#<host> --show-trace
```

Update and deploy:

```bash
sudo nixos-rebuild switch --flake github:<owner>/<repo>#<host> --upgrade --show-trace
```
```

**Nix (non-NixOS):**

```markdown
### Nix (non-NixOS systems)

```bash
nix develop github:<owner>/<repo>
```

The devShell provides <list key packages>.

> [!NOTE]
> <caveat about what doesn't work on non-NixOS>.
```

**Node.js:**

```markdown
### Node.js

Requires Node.js >= <version>.

```bash
npm install
npm run <start-script>
```
```

**Rust:**

```markdown
### Rust

Requires the Rust toolchain (via [rustup](https://rustup.rs/)).

```bash
cargo build --release
cargo run --release
```
```

**Python:**

```markdown
### Python

Requires Python >= <version>.

```bash
pip install .
# or
uv sync
```
```

### 8. Development

Fenced bash block with the devShell or dev environment command, then a numbered list of verification steps (fastest first). End with formatting/lint commands.

```markdown
## Development

Enter the dev environment:

```bash
nix develop .
```

Verify your changes (fastest first):

1. `<check-command>` — catches <what>, no sudo needed.
2. `<build-command>` — dry build.
3. `<deploy-command>` — actual deploy.

Format with `<formatter> --format <file>`; lint with `<linter> <file>`.
```

### 9. Contributing / Adding X (optional)

If the project has a clear extension point (adding a host, a user module, a plugin, a feature), include a short numbered recipe with a minimal code example in a fenced block.

### 10. License

Always end with:

```markdown
## License

This project is licensed under the [MIT License](./LICENSE).
```

Adjust the license name and path to match the actual license file (`LICENSE`, `LICENSE.md`, `LICENCE.md`, `COPYING`).

## Style Rules

- **No preamble.** The file starts with `# <name>`.
- **Badges on one line**, immediately after the title, before the intro paragraph.
- **Fenced code blocks** for all commands, with a language tag (`bash`, `nix`, `json`, etc.).
- **Relative links** for in-repo references (`./LICENSE`, `./AGENTS.md`); absolute URLs for external links.
- **Concise.** Each section should be scannable in < 10 seconds. No filler, no marketing language.
- **Callouts for notes and warnings.** Use GitHub alert syntax, not bold `**Note:**`/`**Warning:**` blockquotes:

  ````markdown
  > [!NOTE]
  > Informational caveat.

  > [!WARNING]
  > Something that will silently break if ignored.
  ````

  Other valid types: `[!TIP]`, `[!IMPORTANT]`, `[!CAUTION]`.
- **Conventional Commit references** are not needed in the README.
- **No emojis** in the README.
- **Table of contents** only when there are 3+ major sections.
- **Max ~150 lines.** If the project is complex, split into `docs/` and link out.

## Validation

After writing the README:

1. Verify the license file path in the badge and the License section match the actual file on disk.
2. Verify the `owner/repo` in badges matches `git remote -v`.
3. Verify all commands in fenced blocks are syntactically plausible (no placeholder `<owner>` left unfilled).
4. If the project has a `flake.nix`, verify the `#<host>` fragment in `nixos-rebuild` commands matches an actual `nixosConfigurations` key.
5. Count top-level `##` headings. If there are 3+ beyond Installation, ensure a TOC is present and matches.
