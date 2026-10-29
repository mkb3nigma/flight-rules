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
  `{TEST_COMMANDS}` run on the commit being pushed — step 2a. Warrant: AppliHawk's
  release PR #191 went red on its first CI run on 2026-09-14 with every merged branch
  individually green, because five merges landed after the batch run and the integration
  branch was never tested whole.
- A release PR also needs `/dg` on the **whole** diff, `origin/main...<sha>` — step 2b —
  with the verdict and every finding's disposition in the PR body, and the `release
  review` check fails a PR into `main` whose **Adversarial review** section is missing
  or empty. Warrant: AppliHawk's
  0.16.0 was declared release-ready on 2026-10-11 with every branch past
  `/pre-merge-check` (which runs no AI review) and the suite green on the final
  integration commit; `/dg` on the 93-commit, 224-file diff the next day found a
  data-loss bug — editing an action unlinked its contact, because a nested response
  schema was a hand-copied subset of the full one and the component test's fixture was
  shaped like the frontend type, not the API payload (fixed in AppliHawk aa4ca42e,
  2026-10-12; private repo). Nothing had reviewed the release as a whole, and the whole
  is the one review with every piece in view at once.
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
2a. **Release PR only** — when the head is `{INTEGRATION_BRANCH}` and the base is `main`:
   before pushing it, run every `{TEST_COMMANDS}` entry on the **exact commit that will
   be pushed**, and stop on any failure. Report the commit sha you ran them on, not just
   that you ran them — "I ran the suite" and "I ran the suite on the commit I am pushing"
   are different claims, and only the second is checkable.

   Per-branch checks prove each change in isolation; the release PR ships the **sum**.
   Nothing has tested the sum until something runs everything on the merged tree. A red
   offline run costs the same minutes as a red CI run and none of anyone's attention.

   A local run covers one platform. Where CI runs the suites on more, read CI's result
   for that same sha (`gh run list --commit <full sha>` — a short sha matches no run,
   and an empty list has nothing red in it; the final 0.25.0 review). It lists workflow
   runs, not platforms: a matrix of OSes is one run, its conclusion covering every job
   (`gh run view <id>` names each). Open the PR only when each workflow CI runs on a
   push is listed for that sha, completed and green — none listed means not yet. 0.25.0's 2a passed on macOS (bash 3.2) while Ubuntu CI
   (bash 5) had been red on `{INTEGRATION_BRANCH}` for two pushes (flight-rules
   4fe21fe, 2026-10-17).
2b. **Release PR only** — run `/dg origin/main...<sha>` on the commit 2a tested,
   preferring a pre-reviewer from a different model family (the skill says why; one
   that is unavailable is a warning in the verdict's header, not a reason to stop), and
   name both shas in the verdict. `/dg` ends its turn with the verdict; dispositions
   follow the owner's reply. Put the `> Pre-review:` / `> Dependency scan:` lines, the verdict (it ends at
   Recommended Actions) and every finding's disposition in the PR body under
   **Adversarial review**, each of the verdict's headings one level down (`###`, `####`;
   the review's own `## Review` title too)
   — a `##` inside the section ends it (outside a code fence), and the check below then finds it empty. No
   round tables or banter. The comic, banter score included, goes in only as the
   project's `DG_COMIC_PR` says (`/dg` step 6; default `never`), as `### Comic` at the
   section's end. The `release review` workflow checks the section is there, holds text
   other than the template's placeholders, and holds a `### Verdict`, outside a code
   fence, with text under it that is not a heading — the header lines alone are not a
   verdict (#83), nor is a bare heading — and re-checks on every body edit. The assistant may decline a minor or important finding with its reason, where the
   owner reads it; a **critical** finding is the owner's to disposition — stop and
   ask. A finding applied arrives like any change, through a branch merged into
   `{INTEGRATION_BRANCH}`; then 2a runs again on the new tip, and `/dg` on the fix's
   own diff only — the rest was reviewed, and that is the exit.

   The same reasoning as 2a, for review instead of tests (the warrant is in the
   constraint above): each branch was checked as a piece, and the release diff is the
   one review with every piece in view at once.

   The body also states what the release adds, by class, from `git diff --numstat
   origin/main...<sha>` — added and net lines by the classes the project's own rules
   name (its `CLAUDE.md` or an `EXTENSIONS.md`): what reaches a session, hook and guard
   code, tests, CI, and everything else, the five summing to the total. The count is evidence,
   not a gate: whether it is proportionate to what the release closes is the owner's
   call, made with the CHANGELOG entry beside the number. flight-rules 0.27.0 added
   4,554 lines, 4,071 of them hook and test code, and no gate recorded the number.
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
