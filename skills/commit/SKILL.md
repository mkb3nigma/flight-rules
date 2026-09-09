---
name: commit
description: Create a git commit with conventional-format validation and a test-coverage warning. Branch protection and secrets scanning are enforced by the hook layer.
argument-hint: "[commit message]"
---

# /commit — Create a Guarded Git Commit

## Project extensions

Before executing, check the consuming project for `.ai/skills/commit/EXTENSIONS.md`.
If present, read it first: it supplies additional or replacement steps, project-specific
rules, and any `{PLACEHOLDER}` values not covered by the conf file below — extensions
take precedence over the generic defaults in this file. If absent, use the defaults
as-is.

Branch and path parameters — `{PROTECTED_BRANCHES}`, `{PR_ONLY_BRANCHES}`,
`{NOTE_GATED_BRANCHES}`, `{INTEGRATION_BRANCH}`, `{WORKTREE_DIR}` — come from
`.ai/flight-rules.conf` and **only** from there: it is what the hooks enforce, so a
value restated in EXTENSIONS.md would be one the enforcement never sees. If both set
one, the conf wins and the extension should be corrected. Anything not set in the conf
falls back to the defaults named in this skill.

## Division of labour

The hooks enforce the hard gates; this skill covers what a hook cannot judge.

- **Hook-enforced** (see `hooks/README.md`): no commits, working-tree destroyers,
  rebases or force-pushes on `{PROTECTED_BRANCHES}`, no deleting one on the remote,
  and no staged secrets (`hooks/agent/pre-commit-check.sh`); no local, squash or
  unstamped merges into PR-only / note-gated branches and no rebase of a PR-only
  branch (`hooks/git/` merge gate).
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
6. **If the guard denies — stop.** Relay the block message to the user verbatim; it
   names the cause and the fix. Never retry with `--no-verify`, `git -C`, a different
   `cd`, a subshell, an alias, or an edit to `.ai/flight-rules.conf`. A variant that
   gets past the guard is a bug report, not a workaround. If the block looks wrong,
   say so and wait — the project owner decides, not the agent that was blocked.
