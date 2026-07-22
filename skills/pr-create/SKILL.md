---
name: pr-create
description: Push the current feature branch and open a GitHub pull request with a pre-merge checklist in the body.
---

# /pr-create — Create a GitHub Pull Request

Open a GitHub PR for the current feature branch. Project parameters:
`{INTEGRATION_BRANCH}`, `{PROTECTED_BRANCHES}`, `{WORKTREE_DIR}`, `{TEST_COMMANDS}`
(defaults: `main` / `main` / `.ai/worktrees/` / the project's test commands).

---

## Rules
- `feature/ fix/ refactor/ test/ docs/ chore/` branches target `{INTEGRATION_BRANCH}` — never a protected branch
- `hotfix/*` targets `main`
- PR title follows conventional-commit format
- Run `/pre-merge-check` before opening the PR — no ❌ items may remain
- Never force-push after opening a PR

## Steps

### 1. Check prerequisites
```bash
git branch --show-current
```
- If on one of `{PROTECTED_BRANCHES}`: STOP — cannot open a PR from a protected branch.
- Determine the base branch:
  - `feature/* fix/* refactor/* test/* docs/* chore/*` → `{INTEGRATION_BRANCH}`
  - `hotfix/*` → `main`
  - anything else → ask the user which base to target

### 2. Ensure the branch is pushed
```bash
git ls-remote --heads origin <branch-name>
```
If it isn't on the remote, push it first:
```bash
git push -u origin <branch-name>
```

### 3. Run pre-merge checks
Run the full `/pre-merge-check`. If any ❌ failures remain, STOP:
> "Pre-merge checks failed. Fix all ❌ items before opening the PR. Run `/pre-merge-check` to verify."

⚠️ warnings are non-blocking but must be listed in the PR body.

### 4. Gather PR content
```bash
git log <base>..HEAD --oneline      # → summary bullets (one per commit)
git diff <base>...HEAD --stat        # → files-changed summary
```

### 5. Generate the PR title
Derive it from the branch name in conventional-commit format:
- `feature/search-filters` → `feature: add search and advanced filters`
- `fix/reset-token-bug` → `fix: correct password-reset token validation`
- `docs/api-reference` → `docs: add API reference`

If arguments are provided, use them as the PR title instead.

### 6. Create the PR
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
Mark any checklist row ❌ if its check failed. A PR should not normally be opened
with ❌ items unless the user explicitly overrides.

### 7. Print the result
Show the PR URL, then print:
```
✅ PR created: <url>

Next steps:
1. Review the diff on GitHub
2. Request a review if needed
3. After merge, clean up the worktree:
   git worktree remove {WORKTREE_DIR}/<slug>
   git branch -d <branch-name>
```
