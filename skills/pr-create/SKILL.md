---
name: pr-create
description: Push the current feature branch and open a GitHub pull request with a pre-merge checklist in the body. Includes the stacked-PR rules that stop work being silently dropped.
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
- **Stacked PRs — see below.** Default to not creating one.

## Stacked PRs

A *stacked* PR is one whose base is another open PR's head rather than
`{INTEGRATION_BRANCH}`. It keeps the second review a clean diff instead of a blob, which
is a real benefit — and it introduces a race that silently drops work.

**What goes wrong:** merging the parent makes GitHub retarget the child to the parent's
base. That retarget is *asynchronous*. Merge the child before it lands and the child's
commits go into the already-merged parent branch — which is then usually auto-deleted.
GitHub reports the child as **MERGED**, truthfully, while its commits never reached
`{INTEGRATION_BRANCH}`. Nothing in the UI flags this.

**Default: don't stack.** Keep the second branch local and open its PR once the parent
merges. Costs a delay, removes the failure mode entirely.

**If you do stack, all four:**

1. **Open the child as a draft** (`gh pr create --draft`). GitHub refuses to merge a
   draft, so the ordering is *enforced* rather than merely documented — the house style
   is guardrails, not etiquette. Mark it ready only once the parent has merged and the
   child's base has visibly flipped to `{INTEGRATION_BRANCH}`.
2. **Put the marker in the TITLE**, not only the body:
   `<conventional title> [stacked on #N — merge #N first]`. The title is what shows in
   the PR list, notification emails, and above the merge button; a body note is one click
   away from where the decision is actually made. Not hypothetical — a PR whose body
   *opened* with "Stacked on #N, review #N first" was still merged out of order, because
   nobody merging from the list opened it.
3. **Open the body with an ordering block** — base branch, which PR merges first, what to
   verify afterwards. The title says *that* it is stacked; the body says what to do.
4. **Verify after merging, never assume.** `MERGED` is a claim about the merge, not about
   the destination:
   ```bash
   git fetch origin && git log --oneline origin/{INTEGRATION_BRANCH} | grep <child-sha>
   ```
   Empty output means the work is stranded on a deleted branch. Recover by re-pushing the
   branch from a local copy and opening a fresh PR against the correct base.

## Procedure

1. Verify the current branch and pick the base per the routing rules; push with
   `git push -u origin <branch>` if the branch isn't on the remote yet. If the chosen
   base is another open PR's head, apply the **Stacked PRs** rules above — add
   `--draft`, put `[stacked on #N — merge #N first]` in the title, and lead the body
   with the ordering block.
2. Run `/pre-merge-check`; STOP on any ❌ failure.
3. Summarize `git log <base>..HEAD` (one user-facing bullet per commit) and
   `git diff <base>...HEAD --stat` (files-changed summary), then create the PR:

```bash
gh pr create \
  --base <base> \
  --title "<title>" \
  --body "$(cat <<'EOF'
<STACKED PRs ONLY — delete this block otherwise. Must be the first thing in the body:>
> ⚠️ **Stacked on #N — merge #N first.** Base is `<parent-branch>`, so this diff shows
> only the new work. Opened as a draft; it will be marked ready once #N merges and this
> PR's base has flipped to `{INTEGRATION_BRANCH}`.
> **After merging both:** confirm this PR's commits actually reached
> `{INTEGRATION_BRANCH}` — a stacked PR can report MERGED having merged into the parent
> branch instead.

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
