---
name: commit
description: Create a git commit with conventional-format validation and a test-coverage warning. Branch protection and secrets scanning are enforced by the hook layer.
---

# /commit — Create a Guarded Git Commit

## Project extensions

Before executing, check the consuming project for `.ai/skills/commit/EXTENSIONS.md`.
If present, read it first: it supplies the project's `{PLACEHOLDER}` values, plus any
additional or replacement steps and project-specific rules — extensions take
precedence over the generic defaults below. If absent, use the defaults as-is.

## Division of labour

The hooks enforce the hard gates; this skill covers what a hook cannot judge.

- **Hook-enforced** (see `hooks/README.md`): no commits on `{PROTECTED_BRANCHES}` and
  no staged secrets (`hooks/agent/pre-commit-check.sh`); no unchecked merges into
  protected branches (`hooks/git/` merge gate).
- **Skill-covered**: commit-message format, test-coverage warning, stray-debug-logging
  warning.

## Rules
- Message starts with `feature:`, `fix:`, `refactor:`, `test:`, `docs:`, or `chore:`
- Commits happen on feature worktrees, not `{PROTECTED_BRANCHES}` (hook-enforced)
- Env files and secrets are never committed (hook-enforced)

## Steps

1. **Show staged changes** — `git diff --cached --stat`.
2. **Test-coverage warning** — if non-test source files are staged with no test file,
   warn plainly that the change ships without a test update, and say so in the commit
   summary to the user. (Files with no test surface — static markup, config — note the
   reason instead.)
3. **Debug-logging warning** — if staged sources contain stray `console.log` / debug
   prints, warn (non-blocking).
4. **Validate the message** — ask if missing; verify the conventional prefix.
5. **Commit** — `git commit -m "<message>"`, appending the assistant's co-author
   trailer if the environment specifies one.
