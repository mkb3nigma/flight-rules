---
name: pr-create
description: Push the current feature branch and open a GitHub pull request with a pre-merge checklist in the body. Covers native stacked PRs (gh stack) and why hand-rolled stacks drop work.
---

# /pr-create — Create a GitHub Pull Request

## Project extensions

Before executing, check the consuming project for `.ai/skills/pr-create/EXTENSIONS.md`.
If present, read it first: it supplies the project's `{PLACEHOLDER}` values, plus any
additional or replacement steps and project-specific rules — extensions take
precedence over the generic defaults below. If absent, use the defaults as-is.

Open a GitHub PR for the current feature branch. Project parameters:
`{INTEGRATION_BRANCH}`, `{PROTECTED_BRANCHES}`, `{WORKTREE_DIR}`, `{TEST_COMMANDS}`
(defaults: `main` / `main` / `.ai/worktrees/` / the project's test commands).

## Constraints
- Never open a PR from one of `{PROTECTED_BRANCHES}`.
- Base-branch routing: `feature/ fix/ refactor/ test/ docs/ chore/` branches target
  `{INTEGRATION_BRANCH}`; `hotfix/*` targets `main`; anything else → ask the user.
- `/pre-merge-check` must be clean first — no ❌ items may remain. ⚠️ warnings are
  non-blocking but must be listed in the PR body.
- PR title in conventional-commit format — derived from the branch name unless the
  user supplies one as arguments.
- Never force-push after opening a PR.
- **Never point `--base` at another open PR's head.** To split work across dependent PRs,
  use GitHub's native stacks (`gh stack`) — see below.

## Stacked PRs — use the real feature, never hand-roll one

Splitting a large change into an ordered series of PRs, each reviewable on its own diff,
is genuinely worth doing. There are two ways to get it, and only one of them is safe.

**Use GitHub's native stacked pull requests.** Public preview since 2026-07-30, all
repositories:

```bash
gh extension install github/gh-stack
```

The platform owns the ordering, which is the whole point:

- Stacks merge **bottom-up**, and a mid-stack PR **cannot** be merged in isolation — the
  PRs below it always merge with it.
- Merging lands the selected PR *and every unmerged PR below it* as one operation.
- The remaining PRs are **automatically rebased** onto the stack base afterwards.
- The merge box shows the status of the **whole stack**, not just the open PR.

Known limits: **auto-merge is not supported** for stacked PRs, and merge-queue support
arrived separately — check both before relying on them.

**Never hand-roll a stack** by pointing `gh pr create --base` at another open PR's head.
It looks identical in the UI and has none of the guarantees:

> Merging the parent makes GitHub retarget the child — *asynchronously*. Merge the child
> before that lands and its commits go into the already-merged parent branch, which is
> then usually auto-deleted. GitHub reports the child as **MERGED**, truthfully, about the
> wrong destination. The commits never reached `{INTEGRATION_BRANCH}` and nothing in the
> UI says so.

This is not hypothetical. It happened in this repo on 2026-08-15 with 22 seconds between
the two merges, and the work survived only because the commit still existed in a local
worktree. A body note reading *"Stacked on #N — review #N first"* was already the first
thing in the child's description and changed nothing, because merging happens from the PR
list and the merge button, and neither shows the body. Ordering that depends on a human
reading prose is not ordering.

**If `gh stack` isn't available** (preview not enabled, non-GitHub host), then don't stack
at all: keep the second branch local and open its PR once the parent merges. Costs a
delay, removes the failure mode entirely. Do not substitute discipline for the mechanism.

**Either way, verify after merging.** `MERGED` is a claim about the merge, not about the
destination:

```bash
git fetch origin && git log --oneline origin/{INTEGRATION_BRANCH} | grep <child-sha>
```

Empty output means the work is stranded on a deleted branch. Recover by re-pushing the
branch from a local copy and opening a fresh PR against the correct base.

## Procedure

1. Verify the current branch and pick the base per the routing rules; push with
   `git push -u origin <branch>` if the branch isn't on the remote yet. If this change
   depends on another open PR, do **not** set that PR's head as the base — use `gh stack`
   (see **Stacked PRs** above) or wait for it to merge.
2. Run `/pre-merge-check`; STOP on any ❌ failure.
3. Summarize `git log <base>..HEAD` (one user-facing bullet per commit) and
   `git diff <base>...HEAD --stat` (files-changed summary), then create the PR:

```bash
gh pr create \
  --base <base> \
  --title "<title>" \
  --body "$(cat <<'EOF'
<STACK MEMBERS ONLY — delete this line otherwise:>
> 📚 Layer <i> of a `gh stack`. Merges bottom-up with the layers below it.

## Summary
<one user-facing bullet per commit, reworded from git log>

## Changes
<files-changed summary from git diff --stat>

## Pre-merge checklist
- [x] Test suite passing (`{TEST_COMMANDS}`)
- [x] Lint / type checks clean
- [x] No secrets in the diff
- [x] No stray debug logging committed
- [x] Conventional-commit format on all commits
- [x] Single, coherent scope
- [x] No merge-conflict markers
- [x] Dependency audit clean
- [x] No tracked env/secret files
- [x] Tests updated alongside source changes

## Warnings
<any ⚠️ items from /pre-merge-check, else "none">

## Testing
- [ ] Happy path exercised
- [ ] Error cases exercised
- [ ] (UI changes) responsive layout + keyboard navigation verified

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Mark any checklist row ❌ if its check failed — a PR should not normally be opened
with ❌ items unless the user explicitly overrides.

4. Show the PR URL. After merge, **verify the commits landed** — `git fetch origin` then
   `git log --oneline origin/{INTEGRATION_BRANCH}` should contain them (mandatory for a
   stacked PR, cheap everywhere else) — then clean up:
   `git worktree remove {WORKTREE_DIR}/<slug>` then `git branch -d <branch-name>`.
   Removing the worktree before verifying can destroy the only local copy of stranded
   commits.
