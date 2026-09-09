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
6. Creating branches with `git checkout -b` / `git switch -c` — always `git worktree add` (hook-enforced)
7. Merging into a protected branch without explicit user instruction
8. Merging into a **PR-only branch (default `main`) locally at all** — it moves only through a reviewed pull request. After the PR merges, sync locally with `git pull --ff-only origin main` (a fast-forward, never a local merge commit).

### ✅ Required
1. All branches created as worktrees under `{WORKTREE_DIR}`
2. Branch names prefixed: `feature/`, `fix/`, `refactor/`, `test/`, `docs/`, `chore/`, `hotfix/`
3. Conventional commit messages using the same prefixes (`hotfix/` branches commit as
   `fix:` — there is no `hotfix:` message prefix)
4. Review the full diff after every commit (`git diff HEAD~1`)
5. Commit after every logical unit of work — small commits, easy rollback
6. Symlink untracked env files from the main checkout into new worktrees
   (copies go stale; symlinks propagate edits): `ln -s "$PWD/.env" {WORKTREE_DIR}/<name>/.env`
7. Clean up after merging: `git worktree remove …` + `git branch -d …` — never leave stale worktrees
8. New branches derive from **`origin/{INTEGRATION_BRANCH}`** after a `git fetch` — never a stale local base. When `{INTEGRATION_BRANCH}` differs from `main`, first reconcile any `main`-only commits back into it (fast-forward / clean merge if possible; **warn and stop** if not) so no branch is born missing a change that went straight to `main`. See the `feature-start` skill, step 4.

## The cwd-drift trap (learned the hard way)

AI shell sessions reset or drift their working directory between commands. Two rules:

- Always `cd <absolute-path>` **in the same shell command** as any git operation.
- Never run `git merge` from inside a feature worktree — it merges into the feature
  branch, not the integration branch. Merge from the main checkout, verified with
  `git branch --show-current` in the same command.
- Run the worktree commit and the integration-branch merge as **separate commands** —
  a compound command that commits in one directory and merges in another is exactly
  how the wrong branch gets merged.

## The merge-collision trap

`git merge` refuses to proceed when a file tracked on the incoming branch also exists
in the main checkout as an untracked or locally-modified copy (common when a parallel
tool or a manual edit produced the same file in both places). Never blind-delete the
local copy: first `diff` it against the branch's version. Byte-identical → remove the
local copy (`rm` untracked / `git checkout -- <file>` modified) and merge. Different →
stop and reconcile; one of the two versions holds work that would be lost.

## Merge flow

```
feature/* → {INTEGRATION_BRANCH} → (staging) → main
```

- Before requesting a merge: run the project's pre-merge checklist (see the
  `pre-merge-check` skill) and an adversarial review (see `dg`) for code changes.
- Bad merge on a protected branch: `git revert -m 1 <merge-sha>` — don't rewrite history.

## Enforcement (optional but recommended)

Ready-made templates for all of the below live in this repo's `hooks/` directory.
Commit the hooks into the project (e.g. `.ai/hooks/`) and point git at them once per clone:

- The merge gate, three git hooks plus `post-merge` (`install.sh` refuses to install
  unless all four are present, then runs `git config core.hooksPath <dir>` and
  `git config merge.ff false` — the second matters: a fast-forward creates no merge
  commit, so without it no gate hook ever fires):
  `pre-merge-commit` blocks any local merge into a **PR-only** branch
  (`{PR_ONLY_BRANCHES}`, default `main`); `commit-msg` requires a passing
  `pre-merge-check` note to merge into a **note-gated** branch
  (`{NOTE_GATED_BRANCHES}`), exempting back-merges of `main`, and refuses squash
  merges into a PR-only branch; `pre-rebase` refuses to rebase one. All read
  `.ai/flight-rules.conf` **as committed on the merge target**, so an incoming branch
  cannot relax the rule judging it.
- `hooks/agent/pre-commit-check.sh`, the assistant-side guard — commits, tree
  destroyers, rebases and force-pushes on a protected branch; staged secrets anywhere.
  Ships with the Claude Code plugin. Details: `hooks/README.md`.
