---
name: feature-start
description: Create a new feature branch as a git worktree following the playbook's strict branching rules.
argument-hint: "<prefix/branch-name>"
---

# /feature-start — Create a Feature Branch Worktree

## Project extensions

Before executing, check the consuming project for `.ai/skills/feature-start/EXTENSIONS.md`.
If present, read it first: it supplies additional or replacement steps, project-specific
rules, and any `{PLACEHOLDER}` values not covered by the conf file below — extensions
take precedence over the generic defaults in this file. If absent, use the defaults
as-is.

Branch and path parameters — `{PROTECTED_BRANCHES}`, `{PR_ONLY_BRANCHES}`,
`{NOTE_GATED_BRANCHES}`, `{INTEGRATION_BRANCH}`, `{WORKTREE_DIR}` — come from
`.ai/flight-rules.conf` and **only** from there: it is what the hooks enforce, so a
value restated in EXTENSIONS.md would be one the enforcement never sees. If both set
one, the conf wins and the extension should be corrected. Anything not set in the conf
falls back to the defaults named in this skill.

Create a new branch as a git worktree per `rules/git-worktree-workflow.md`.
Project parameters: `{PROTECTED_BRANCHES}`, `{INTEGRATION_BRANCH}`, `{WORKTREE_DIR}`
(defaults: `main` / `main` / `.ai/worktrees/`).

## Rules (non-negotiable)
- NEVER `git checkout -b` / `git switch -c` — always `git worktree add`
- All branches live under `{WORKTREE_DIR}`
- Branch name must start with an allowed prefix: `feature/`, `fix/`, `refactor/`, `test/`, `docs/`, `chore/`, `hotfix/`

## Steps

1. **Check current branch** — the main checkout normally rests on `{INTEGRATION_BRANCH}`;
   that's fine (worktree creation never commits to it). If the working tree is dirty,
   stop and ask what to do with the changes.
2. **Check stashes** — `git stash list`; if any exist, list them and ask whether to
   proceed or resolve first.
3. **Validate the branch name** — ask if not provided; verify the prefix.
4. **Sync the base from origin — non-negotiable.**
   - `git fetch origin` first, **always**. New branches derive from
     **`origin/{INTEGRATION_BRANCH}`** (the true remote state) — never a local copy
     that may be behind. Branching off a stale local base is the exact way work gets
     built on the wrong foundation.
   - **Reconcile `main` into the integration branch** — only when
     `{INTEGRATION_BRANCH}` differs from `main`. A hotfix or change applied straight
     to `main` is not on the integration branch, so a branch built off it silently
     misses it. Check:
     ```bash
     git log --oneline origin/{INTEGRATION_BRANCH}..origin/main
     ```
     If non-empty, fast-forward the integration branch on the remote BEFORE
     branching — without touching any local checkout:
     ```bash
     git push origin origin/main:refs/heads/{INTEGRATION_BRANCH} && git fetch origin
     ```
     A push is refused when it is not a fast-forward. That refusal means the branches
     have diverged and reconciling them is a real merge into a protected branch, which
     the workflow rule reserves for an explicit user decision. STOP, show both
     `git log` ranges, and ask. Never run `git merge` here yourself.
   - **No remote?** (`git remote` prints nothing): branch from the local
     `{INTEGRATION_BRANCH}`, skip the fetch and the reconcile, and say so in the
     confirmation.
5. **Create the worktree** from `origin/{INTEGRATION_BRANCH}` (repo root, absolute paths):
   ```bash
   git worktree add {WORKTREE_DIR}/<slug> -b <full-branch-name> origin/{INTEGRATION_BRANCH}
   ```
6. **Symlink untracked env files** from the main checkout (symlinks, not copies —
   copies go stale):
   ```bash
   ln -s "$PWD/<path>/.env" {WORKTREE_DIR}/<slug>/<path>/.env
   ```
   Skip with a warning if the source file is missing. This step is required even when
   a worktree was created with a raw `git worktree add` instead of this skill — a
   worktree running without its env files fails in confusing ways (missing keys,
   stale service URLs).

   Heavyweight untracked dirs are NOT all symlink-safe: interpreter venvs generally
   tolerate a symlink, but **do not symlink `node_modules`** — dev tools that resolve
   real paths (e.g. the Vite dev server) break through the link. Run a fresh
   `npm ci` in the worktree instead.
7. **Confirm** — print the worktree path, the `cd` command, and the reminder:
   "Work only in this directory. ONE purpose per branch." If the repo ships git hooks
   and `core.hooksPath` isn't set, print the one-time install command.
8. **List worktrees** — `git worktree list`.

## Cleanup (after merge — required, never leave stale worktrees)

```bash
git worktree remove {WORKTREE_DIR}/<slug>
git branch -d <branch>
git branch --merged {INTEGRATION_BRANCH} | grep -vE '^\*|{PROTECTED_BRANCHES}' | xargs -r git branch -d
```
