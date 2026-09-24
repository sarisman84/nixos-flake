# Persistent Instructions

These instructions apply to all projects. They define how I (the agent) should work with you.

## General Behavior

- **Act first, ask for validation.** Do not wait for permission to start work. Complete the task, then ask you to validate the result.
- **Always test your work.** For any project, verify your changes work. If you are unsure how to test, either set up a minimal testing environment or ask you how to test.
- **Error handling:** On encountering an error, attempt to fix it automatically up to 3 times. If it consistently fails after 3 attempts, stop and ask you for help.
- **Never touch sensitive files.** Do not read, modify, or commit `.env` files, secrets, keys, or credentials. Never write secrets into code or flake output.
- **Follow best practices for version control**, including feature-based workflows (see below).

## Pre-Task Questionnaire

- Ask for clarity **only when the request is ambiguous**. Do not ask unnecessary questions.
- When asking, ask anything relevant to the topic — not limited to the current project.
- Keep questions to a maximum of **10** before proceeding.
- If after asking the request is still ambiguous, state your assumptions clearly and proceed.

## Version Control

### Commit Messages
- Use **Conventional Commits**: `feat:`, `fix:`, `chore:`, `refactor:`, `docs:`, `test:`, `style:`, `perf:`, `build:`, `ci:`.
- Format: `<type>: <concise summary>` (imperative mood, no trailing period).
- Add a body only when the summary is insufficient; keep it brief.

### Branch Naming
- Conventional prefixes:
  - `feature/<short-description>`
  - `fix/<short-description>`
  - `chore/<short-description>`
  - `docs/<short-description>`
  - `refactor/<short-description>`
- Use kebab-case for the description.

### Branching Workflow
- **Always create a branch from the most up-to-date default branch before working on a task.** Update the default branch first (e.g. `git fetch && git checkout <default> && git pull --rebase`), then branch off it. Do not work on the default branch for features.
- Small, isolated fixes may be made directly on the default branch if they are trivial (single-line, no logic change) — otherwise branch.
- If unsure which branch is the default, check `git remote show origin` (look for "HEAD branch").

### Commit Granularity
- Commit **granularly** — one logical change per commit — to make work traceable and easy to revert.
- **Ask before committing large or meaningful changes** (new features, breaking changes, multi-file refactors).
- **Automatically commit smaller, less important changes** (typos, formatting, minor fixes, intermediate safe steps).

### Rebase vs Merge
- **Prefer rebasing over merging.** Keep history linear.
- Rebase feature branches onto the base branch before opening a PR or merging back.
- Do not force-push shared branches without confirming first.

### Pull Request Conventions
- Draft PRs using the template below. Fill in all sections; omit a section only if genuinely not applicable (state "N/A" rather than leaving it empty).
- **Owner:** Always assign the user (the repository owner) as the PR owner when creating a PR.
- **Labels:** Add an appropriate label (`feature`, `fix`, `chore`, `docs`, `refactor`).
- **PR title:** Reflect the branch name — convert `prefix/description` to `Prefix - Detailed description`. Capitalize the prefix, use a human-readable detailed description of the work.
  - Example: branch `feature/foo-bar` → PR title `Feature - New Foo Bar Element added`.
  - Example: branch `fix/login-redirect` → PR title `Fix - Login redirect loop on OAuth callback`.

#### PR Template
```markdown
## Summary
<!-- 1-2 sentences: what this PR does and why -->

## Changes
<!-- Bullet list of the main additions, removals, and modifications -->
- 

## Testing
<!-- How this was tested: commands run, environments, edge cases covered -->
- 

## Validation
<!-- What the user should check to validate this work -->
- 
```

## Documentation

- **When:** Only when you clarify or explicitly ask for documentation.
- **Where:** A dedicated `docs/` directory in the project the request was made in. Create it if it does not exist.
- **AGENTS.md updates:** Automatically update the project's `AGENTS.md` when changes are made that affect how I work in that project (new conventions, new commands, structural changes, gotchas).
- **Language:** Concise and technical. No filler, no verbose explanations. State facts, commands, and constraints directly.
- **Code formatting:** Any code-related text — commands, file paths, option names, identifiers, and code snippets — must use appropriate markdown formatting.
  - Inline code (single backticks): commands, file paths, options, flags, identifiers. E.g. `nix flake check`, `~/.config/opencode/AGENTS.md`, `pkgs`, `home.file.".config/opencode/opencode.json"`.
  - Fenced code blocks (triple backticks, with a language tag): multi-line code, scripts, config blocks, command sequences.
  - Never leave code-related text as plain prose.
- **Size limit:** Keep each document small — target ~150 lines of text maximum. If a document would exceed the limit, split the content where it makes sense into a new document and reference it from the original (relative markdown link) instead of growing the original unboundedly.
  - The original document keeps a brief summary + a link to the split-out document.
  - Choose split points at natural topic boundaries (a section, a concern, a command group).
