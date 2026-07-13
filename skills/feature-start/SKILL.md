---
name: feature-start
description: Create a new feature branch as a git worktree following the playbook's strict branching rules.
---

# /feature-start — Create a Feature Branch Worktree

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
4. **Update the base** — `git fetch origin {INTEGRATION_BRANCH}` and report whether the
   local base is behind.
5. **Create the worktree** (from the repo root, absolute paths):
   ```bash
   git worktree add {WORKTREE_DIR}/<slug> -b <full-branch-name> {INTEGRATION_BRANCH}
   ```
6. **Symlink untracked env files** from the main checkout (symlinks, not copies —
   copies go stale):
   ```bash
   ln -s "$PWD/<path>/.env" {WORKTREE_DIR}/<slug>/<path>/.env
   ```
   Skip with a warning if the source file is missing. If the project has heavyweight
   untracked dirs (venv, node_modules), symlink them the same way when a task needs them.
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
