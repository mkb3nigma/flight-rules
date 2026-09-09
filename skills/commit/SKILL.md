---
name: commit
description: Create a git commit with conventional-format validation and a test-coverage warning. Branch protection and secrets scanning are enforced by the hook layer.
argument-hint: "[commit message]"
---

# /commit — Create a Guarded Git Commit

## Project extensions

Read `.ai/skills/commit/EXTENSIONS.md` first if the project has one: extra or
replacement steps, project rules, and `{PLACEHOLDER}` values. It overrides the
defaults below. Branch and path parameters (`{PROTECTED_BRANCHES}`,
`{PR_ONLY_BRANCHES}`, `{NOTE_GATED_BRANCHES}`, `{INTEGRATION_BRANCH}`, `{WORKTREE_DIR}`)
come **only** from `.ai/flight-rules.conf`, the file the hooks read — an extension
restating one is invisible to enforcement, so the conf wins.

## Division of labour

The hooks enforce the hard gates; this skill covers what a hook cannot judge.

- **Hook-enforced** (`hooks/README.md`): nothing that commits to, rewrites, discards
  from or force-pushes a protected branch; no staged secrets; no local, squash or
  unstamped merge into a gated branch.
- **Skill-covered**: commit-message format, test-coverage warning, stray-debug-logging
  warning.

## Rules
- Message starts with `feature:`, `fix:`, `refactor:`, `test:`, `docs:`, or `chore:`
  (a `hotfix/` branch carries `fix:` commits — there is no `hotfix:` prefix)
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
6. **If the guard denies — stop.** Relay the block message verbatim; it names the
   cause and the fix. Never retry with `--no-verify`, `-C`, another `cd`, a subshell,
   an alias or a conf edit: a variant that gets past the guard is a bug report. If the
   block looks wrong, say so and wait — the owner decides, not the blocked agent.
