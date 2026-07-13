# Git Worktree Workflow

Branch discipline for AI-assisted development. Parameterized: a project defines
`{PROTECTED_BRANCHES}` (e.g. `main`, `staging`, `dev`), `{INTEGRATION_BRANCH}` (where
feature work merges), and `{WORKTREE_DIR}` (e.g. `.ai/worktrees/`).

## Why worktrees

AI assistants drift: a shell `cd` here, an edit there, and suddenly a feature change
lands on a protected branch. Worktrees make the working directory itself encode the
branch — feature work physically cannot dirty the main checkout.

## Rules

### 🚫 Forbidden
1. Direct commits to any of `{PROTECTED_BRANCHES}`
2. Multiple features in one branch — one purpose per branch
3. Starting a new feature before merging (or parking) the current one
4. Merging without tests passing
5. Force-pushing protected branches
6. Creating branches with `git checkout -b` / `git switch -c` — always `git worktree add`
7. Merging into a protected branch without explicit user instruction

### ✅ Required
1. All branches created as worktrees under `{WORKTREE_DIR}`
2. Branch names prefixed: `feature/`, `fix/`, `refactor/`, `test/`, `docs/`, `chore/`, `hotfix/`
3. Conventional commit messages using the same prefixes
4. Review the full diff after every commit (`git diff HEAD~1`)
5. Commit after every logical unit of work — small commits, easy rollback
6. Symlink untracked env files from the main checkout into new worktrees
   (copies go stale; symlinks propagate edits): `ln -s "$PWD/.env" {WORKTREE_DIR}/<name>/.env`
7. Clean up after merging: `git worktree remove …` + `git branch -d …` — never leave stale worktrees

## The cwd-drift trap (learned the hard way)

AI shell sessions reset or drift their working directory between commands. Two rules:

- Always `cd <absolute-path>` **in the same shell command** as any git operation.
- Never run `git merge` from inside a feature worktree — it merges into the feature
  branch, not the integration branch. Merge from the main checkout, verified with
  `git branch --show-current` in the same command.

## Merge flow

```
feature/* → {INTEGRATION_BRANCH} → (staging) → main
```

- Before requesting a merge: run the project's pre-merge checklist (see the
  `pre-merge-check` skill) and an adversarial review (see `dg`) for code changes.
- Bad merge on a protected branch: `git revert -m 1 <merge-sha>` — don't rewrite history.

## Enforcement (optional but recommended)

Commit the hooks into the repo (e.g. `.ai/hooks/`) and point git at them once per clone:

- `pre-merge-commit` — blocks merges into `{PROTECTED_BRANCHES}` unless the pre-merge
  check stamped a passing git note (`refs/notes/pre-merge-check`) on the incoming HEAD
- `git config core.hooksPath <hooks-dir>` + `git config merge.ff false` (so the hook
  always fires)
- A session-start / prompt hook that blocks commits while on a protected branch
