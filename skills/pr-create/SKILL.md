---
name: pr-create
description: Push the current feature branch and open a GitHub pull request with a pre-merge checklist in the body. Covers native stacked PRs (gh stack) and why hand-rolled stacks drop work.
argument-hint: "[PR title]"
---

# /pr-create — Create a GitHub Pull Request

## Project extensions

Read `.ai/skills/pr-create/EXTENSIONS.md` first if the project has one: extra or
replacement steps, project rules, and `{PLACEHOLDER}` values. It overrides the
defaults below. Branch and path parameters (`{PROTECTED_BRANCHES}`,
`{PR_ONLY_BRANCHES}`, `{NOTE_GATED_BRANCHES}`, `{INTEGRATION_BRANCH}`, `{WORKTREE_DIR}`)
come **only** from `.ai/flight-rules.conf`, the file the hooks read — an extension
restating one is invisible to enforcement, so the conf wins.

Open a GitHub PR for the current feature branch. Project parameters:
`{INTEGRATION_BRANCH}`, `{PROTECTED_BRANCHES}`, `{WORKTREE_DIR}`, `{TEST_COMMANDS}`
(defaults: `main` / `main` / `.ai/worktrees/` / the project's test commands).

## Constraints
- Never open a PR from one of `{PROTECTED_BRANCHES}` — **except the release PR**, whose
  head is `{INTEGRATION_BRANCH}` and whose base is `main`. On a two-branch project the
  integration branch is usually protected too, so without this exception the skill
  forbids the release it describes in step 2a.
- Base-branch routing: `feature/ fix/ refactor/ test/ docs/ chore/` branches target
  `{INTEGRATION_BRANCH}`; `hotfix/*` targets `main`; anything else → ask the user.
- `/pre-merge-check` must be clean first — no ❌ items may remain. ⚠️ warnings are
  non-blocking but must be listed in the PR body.
- A release PR (`{INTEGRATION_BRANCH}` → `main`) additionally needs the full
  `{TEST_COMMANDS}` run on the commit being pushed (step 2a) and `/dg` on the **whole**
  diff, `origin/main...<sha>`, with the verdict and every finding's disposition in the PR
  body (step 2b). `release-pr.md` beside this file has both steps in full and their
  warrants.
- PR title in conventional-commit format — derived from the branch name unless the
  user supplies one as arguments.
- Never force-push after opening a PR.
- **Never point `--base` at another open PR's head.** To split work across dependent PRs,
  use GitHub's native stacks (`gh stack`) — see below.

## Stacked PRs — use the real feature, never hand-roll one

To split a change into dependent PRs, use GitHub's native stacks (`gh stack`), or keep
the second branch local until the first merges. Never point `--base` at another open
PR's head: GitHub can merge the child into the parent's branch, report it MERGED, and
the work never reaches `{INTEGRATION_BRANCH}` (this repo, 2026-08-15). Either way,
verify after merging. `stacked-prs.md` beside this file has the commands, what the
platform guarantees and the failure in full — read it before stacking.

## Procedure

1. Verify the current branch and pick the base per the routing rules; push with
   `git push -u origin <branch>` if the branch isn't on the remote yet. If this change
   depends on another open PR, do **not** set that PR's head as the base — use `gh stack`
   (see **Stacked PRs** above) or wait for it to merge.
2. Run `/pre-merge-check`; STOP on any ❌ failure.
2a. **Release PR only** — when the head is `{INTEGRATION_BRANCH}` and the base is `main`:
   run every `{TEST_COMMANDS}` entry on the exact commit that will be pushed, stop on
   any failure, and report that sha; where CI runs more platforms, open the PR only
   once CI is green for it. `release-pr.md` beside this file, 2a, has how to read CI.
2b. **Release PR only** — `/dg origin/main...<sha>` on the commit 2a tested. The
   verdict, every finding's disposition and the lines the release adds by class go in
   the PR body under **Adversarial review**; a critical finding is the owner's to
   disposition. `release-pr.md` beside this file, 2b, has the section's format — what
   the `release review` check reads — and what follows a finding applied.
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
<the /pre-merge-check table, pasted verbatim — a retyped summary drops rows>

## Warnings
<any ⚠️ items from /pre-merge-check, else "none">

<RELEASE PRs ONLY — delete this section otherwise; on a release PR delete this line:>
## Adversarial review
<the /dg verdict on origin/main...<sha> — its header lines, then the verdict through Recommended Actions with every heading one level down, no banter — naming both shas, and each finding's disposition: applied (branch/commit), declined (reason), or — a critical — the owner's call, quoted>
<ONLY if DG_COMIC_PR is always, or ask and the owner said yes — delete this line otherwise:>
### Comic
<the ASCII comic from /dg, its fence and banter score included>

## Testing
- [ ] Happy path exercised
- [ ] Error cases exercised
- [ ] (UI changes) responsive layout + keyboard navigation verified

<the assistant's attribution footer, if the environment specifies one — else omit>
EOF
)"
```

Do not open a PR with ❌ rows unless the user overrides. The **Testing** rows ship
unticked on purpose: tick a row only for what you actually exercised, and **delete** a
row that does not apply (a UI row on a backend change). Never tick by default — a box
is an attestation — and never leave an inapplicable row unticked, which GitHub's task
counter reports as unfinished work.

4. Show the PR URL. After merge, **verify the commits landed** — `git fetch origin` then
   `git log --oneline origin/{INTEGRATION_BRANCH}` should contain them (mandatory for a
   stacked PR, cheap everywhere else) — then clean up:
   `git worktree remove {WORKTREE_DIR}/<slug>` then `git branch -d <branch-name>`.
   Removing the worktree before verifying can destroy the only local copy of stranded
   commits.
