# Git Worktree Workflow

Branch discipline for AI-assisted development. Parameterized: a project defines
`{PROTECTED_BRANCHES}` (e.g. `main`, `staging`, `dev`), `{INTEGRATION_BRANCH}` (where
feature work merges), and `{WORKTREE_DIR}` (e.g. `.ai/worktrees/`).

## Why worktrees

AI assistants drift: a shell `cd` here, an edit there, and suddenly a feature change
lands on a protected branch. Worktrees make the working directory itself encode the
branch — feature work physically cannot dirty the main checkout.

## Rules

Each item says how it is enforced — **hook**, **skill**, or **advisory**. Advisory
items are reviewed at every plugin release and either given enforcement or deleted.

### 🚫 Forbidden
1. Direct commits to any of `{PROTECTED_BRANCHES}` — hook
2. Multiple features in one branch — one purpose per branch — skill (`pre-merge-check` 9, ⚠️)
3. Starting a new feature before merging (or parking) the current one — advisory
4. Merging without tests passing — skill (`pre-merge-check` 1–3 runs them; on note-gated
   branches `commit-msg` requires its stamp, which proves the skill ran, not that it
   passed honestly); on PR-only branches the host's CI and review are the gate
5. Force-pushing or rebasing a protected branch, or deleting it — locally or on the
   remote — hook
   (agent guard; the `pre-rebase` git hook covers PR-only branches only)
6. Creating branches with `git checkout -b` / `git switch -c` — always `git worktree add` — hook
7. Moving a **PR-only branch (default `main`) onto anything not already on its remote**
   — merging locally, committing directly, cherry-picking, reverting, `branch -f`,
   `update-ref`, `reset --hard`. It moves only through a reviewed pull request. Sync
   with `git pull --ff-only origin main` — hook (`reference-transaction`, which judges
   where the ref landed rather than which command moved it)
8. Merging into any other protected branch **without the user's instruction** — the
   `pre-merge-check` stamp is the agent's own, so it shows a check ran, not that anyone
   wanted the merge. Refused unless the merge says so:
   `FLIGHT_RULES_MERGE_AUTHORISED=1 git merge …`, which is recorded in the merge commit
   as a `Merge-authorisation:` trailer. Setting that variable when the user did not ask
   is the thing this forbids — the hook cannot tell, the trailer makes it auditable.
   A project that does not want the check sets `MERGE_NEEDS_INSTRUCTION=off`; that is
   recorded in the trailer too — hook (`commit-msg`)

### ✅ Required
1. All branches created as worktrees under `{WORKTREE_DIR}` — hook for "as worktrees"
   (Forbidden 6); the location is advisory
2. Branch names prefixed: `feature/`, `fix/`, `refactor/`, `test/`, `docs/`, `chore/`, `hotfix/` — skill (`feature-start` 3)
3. Conventional commit messages using the same prefixes (`hotfix/` branches commit as
   `fix:` — there is no `hotfix:` message prefix) — skill (`commit` 4, `pre-merge-check` 8)
4. Review the full diff after every commit (`git diff HEAD~1`) — advisory
5. Commit after every logical unit of work — small commits, easy rollback — advisory
   (`pre-merge-check` 16 only warns at the other extreme, ~20+)
6. Symlink untracked env files from the main checkout into new worktrees
   (copies go stale; symlinks propagate edits): `ln -s "$PWD/.env" {WORKTREE_DIR}/<name>/.env`.
   Not `node_modules` — tools that resolve real paths break through the link — skill (`feature-start` 6)
7. Clean up after merging: `git worktree remove …` + `git branch -d …` — reminded (`post-merge`, `session-start`)
8. New branches derive from **`origin/{INTEGRATION_BRANCH}`** after a `git fetch` — never a stale local base. When `{INTEGRATION_BRANCH}` differs from `main`, first fast-forward any `main`-only commits into it; if that is not a fast-forward, **stop and ask** — skill (`feature-start` 4)

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
trunk-based ({INTEGRATION_BRANCH} = main):  feature/* ──PR──▶ main
git-flow:  feature/* ──▶ {INTEGRATION_BRANCH} ──▶ (staging) ──PR──▶ main
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
