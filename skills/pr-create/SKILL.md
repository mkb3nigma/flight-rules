---
name: pr-create
description: Push the current feature branch and open a GitHub pull request with a pre-merge checklist in the body.
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

## Procedure

1. Verify the current branch and pick the base per the routing rules; push with
   `git push -u origin <branch>` if the branch isn't on the remote yet.
2. Run `/pre-merge-check`; STOP on any ❌ failure.
3. Summarize `git log <base>..HEAD` (one user-facing bullet per commit) and
   `git diff <base>...HEAD --stat` (files-changed summary), then create the PR:

```bash
gh pr create \
  --base <base> \
  --title "<title>" \
  --body "$(cat <<'EOF'
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

4. Show the PR URL. After merge, clean up:
   `git worktree remove {WORKTREE_DIR}/<slug>` then `git branch -d <branch-name>`.
