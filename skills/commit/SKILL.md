---
name: commit
description: Create a git commit enforcing playbook commit-time rules — protected-branch guard, secrets scan, test-coverage check, conventional format, post-commit diff review.
---

# /commit — Create a Guarded Git Commit

## Rules (non-negotiable)
- NEVER commit while on any of `{PROTECTED_BRANCHES}` — feature worktrees only
- Message MUST start with: `feature:`, `fix:`, `refactor:`, `test:`, `docs:`, or `chore:`
- Tests updated or added for every source-code change
- Review the full diff after committing
- NEVER commit env files or secrets

## Steps

1. **Branch guard** — `git branch --show-current`; on a protected branch, STOP and
   direct the user to a feature worktree (see `/feature-start`).
2. **Show staged changes** — `git diff --cached --stat`.
3. **Secrets scan** — scan the staged diff for cloud-key patterns
   (`AKIA[A-Z0-9]{16}`), API-key literals (`sk-[a-zA-Z0-9]{32,}`), private-key
   headers, and hardcoded credential assignments. Any hit → STOP, list findings
   (values redacted), proceed only on explicit confirmation.
4. **Debug-logging check** — grep staged sources for stray `console.log` / debug
   prints. Warn (non-blocking), ask whether to proceed.
5. **Test-coverage check** — if non-test source files are staged with no test file,
   warn: "No test file is included. Every code change requires a test update.
   Continue anyway?" Wait for explicit confirmation. (Files with no test surface —
   static markup, config — note the reason instead.)
6. **Validate the message** — ask if missing; verify the prefix.
7. **Commit** — `git commit -m "<message>"`, appending the assistant's co-author
   trailer if the environment specifies one.
8. **Post-commit diff review** — run `git diff HEAD~1` and actually review it; this is
   mandatory, not ceremonial.
