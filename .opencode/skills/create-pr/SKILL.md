---
name: create-pr
description: Creates or updates a GitHub pull request following the repo's conventions. Use when the user asks to create, open, or raise a PR, or to push a branch for review. Always creates a DRAFT PR first and asks the user to validate; only converts it to a regular PR once the user is satisfied. Handles branching from the latest default branch, PR title from the branch name, label selection, owner assignment, the Summary/Changes/Testing/Validation template, and updating an existing PR when new commits land.
---

# Create PR

Create (or update) a GitHub pull request that matches this repo's conventions. The result must be a PR with the correct title, label, owner, and a fully-filled body.

**Draft-first policy:** Always open the PR as a **draft** and ask the user to validate it. Do **not** mark it ready for review until the user explicitly says they are satisfied. When new commits or changes land, keep the PR a draft and re-ask. Only convert a draft to a regular PR on the user's explicit approval.

## Workflow

### 1. Inspect the branch

Before doing anything, establish the facts:

```bash
git branch --show-current          # current branch
git remote show origin | grep "HEAD branch"   # default branch (usually main)
git fetch origin
git log --oneline <default>..HEAD   # commits this PR will contain
git diff --stat <default>...HEAD    # files changed
git status                          # anything uncommitted?
gh pr list --head <branch> --state open   # is there already an open PR?
```

- If there are **uncommitted changes**, stop and commit (or ask) before pushing.
- If an **open PR already exists** for this head branch, this is an **update**, not a new PR (see step 6).

### 2. Branch from the latest default branch

Never open a PR off a stale base. If the current branch was not cut from the latest default:

```bash
git fetch origin
git checkout <default> && git pull --rebase
git checkout -b <prefix>/<kebab-description>   # if not already on a feature branch
```

Branch naming (kebab-case description):

| Prefix | Use for |
|---|---|
| `feature/` | new functionality |
| `fix/` | bug fixes |
| `chore/` | maintenance, deps, tooling |
| `docs/` | documentation only |
| `refactor/` | restructuring without behavior change |

Small single-line fixes with no logic change may go straight to the default branch; otherwise always branch.

### 3. Rebase onto the default

Keep history linear:

```bash
git checkout <branch>
git rebase <default>
```

Resolve conflicts, then `git rebase --continue`. Do **not** force-push a shared branch without confirming first.

### 4. Derive the PR title from the branch name

Convert `prefix/description` → `Prefix - Detailed description`. Capitalize the prefix, expand the kebab description into a human-readable phrase.

- `feature/foo-bar` → `Feature - New Foo Bar Element added`
- `fix/login-redirect` → `Fix - Login redirect loop on OAuth callback`
- `docs/add-readme` → `Docs - Add project README and create-readme skill`

### 5. Pick the label

Exactly one primary label from the repo's label set:

| Label | Use when |
|---|---|
| `bug` | something isn't working |
| `fix` | fixes a bug or a deprecation |
| `enhancement` | new feature or request |
| `refactor` | code restructuring, no behavior change |
| `documentation` | docs additions or improvements |

If the repo has no labels yet, `gh label create <name>` the ones you need first.

### 6. Create or update (always draft-first)

**New PR — create as a draft:**

```bash
gh pr create \
  --draft \
  --base <default> \
  --head <branch> \
  --title "<Prefix - Detailed description>" \
  --label <label> \
  --body "<filled template, see step 7>"
```

`gh` assigns the authenticated user (the repo owner) as the author/owner by default — confirm it is the user, not a bot.

**Existing PR — update, keep it a draft:** when `gh pr list --head <branch>` found an open PR, do **not** open a duplicate. Push the new commits, then update the body:

```bash
git push
gh pr edit <number> --body "<updated template>"
# also update the title/label if the work's nature changed
```

If the existing PR is already a regular (non-draft) PR and new changes land, leave it as-is unless the user asks — but if you are the one re-opening work, prefer `gh pr ready <number> --undo` to drop it back to draft while you iterate.

### 6b. Ask for validation, then convert on approval

After creating or updating the draft, **stop and ask the user** whether they are satisfied with the result (the diff, the PR body, and the validation steps). Do not mark it ready on your own.

- **If the user makes changes or asks for edits:** commit them, push, update the draft body, and ask again. Stay a draft.
- **If the user is satisfied:** convert the draft to a regular PR:

  ```bash
  gh pr ready <number>
  ```

  Then return the PR URL and confirm it is ready for review.

Never run `gh pr ready` without an explicit "I'm satisfied / make it ready / convert it" from the user.

### 7. Fill the body template

Always use this structure. Fill every section; write `N/A` only when a section is genuinely not applicable.

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

Guidance per section:

- **Summary** — the *why* and the *what*, in plain language. One or two sentences.
- **Changes** — derived from `git diff --stat <default>...HEAD` and `git log --oneline <default>..HEAD`. List the significant additions, removals, and modifications. Group related changes.
- **Testing** — the concrete commands you ran and their outcome (e.g. `nix flake check` passed, `sudo nixos-rebuild build --flake .#two-b` succeeded). If you ran no tests, say so honestly and what would be needed.
- **Validation** — actionable steps for the user: what to open, what command to run, what to look for. Make it copy-pasteable.

## Conventions

- **Conventional Commits** on the underlying commits: `<type>: <concise summary>` (imperative, no trailing period). Types: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`, `style`, `perf`, `build`, `ci`.
- **Granular commits** — one logical change per commit.
- **Ask before committing** large or meaningful changes; auto-commit small safe ones.
- **Never** commit secrets, `.env` files, or credentials.
- **Rebase, don't merge**, feature branches into the default.
- **Draft-first:** open as a draft, ask the user to validate, and only run `gh pr ready <number>` after the user explicitly approves.
- After creating or updating, return the **PR URL** to the user (noting it is a draft until approved).

## Validation

Before reporting done:

1. `gh pr view <number> --json title,labels,author,baseRefName,headRefName,url,isDraft` — confirm title matches the branch-name convention, exactly one correct label, author is the user, base is the default branch, and `isDraft` is `true` (unless the user already approved and it was converted).
2. The body has all four sections filled (no empty `<!-- -->` placeholders left, no `N/A` unless justified).
3. If this was an update, the PR body reflects the new commits.
4. You have asked the user for validation and have **not** run `gh pr ready` unless they explicitly approved.
