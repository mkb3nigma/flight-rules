---
name: pre-merge-check
description: Run the automated pre-merge checklist for the current feature branch. No AI review — safe to run repeatedly. Stamps a git note the merge-guard hook can verify.
---

# /pre-merge-check — Automated Pre-Merge Checklist

## Project extensions

Read `.ai/skills/pre-merge-check/EXTENSIONS.md` first if the project has one: extra or
replacement steps, project rules, and `{PLACEHOLDER}` values. It overrides the
defaults below. Branch and path parameters (`{PROTECTED_BRANCHES}`,
`{PR_ONLY_BRANCHES}`, `{NOTE_GATED_BRANCHES}`, `{INTEGRATION_BRANCH}`, `{WORKTREE_DIR}`)
come **only** from `.ai/flight-rules.conf`, the file the hooks read — an extension
restating one is invisible to enforcement, so the conf wins.

Run every automated check before merging a feature branch into its destination
(default: `{INTEGRATION_BRANCH}`). Prints a pass/fail report and stamps a git note when
clean so a `pre-merge-commit` hook can allow the merge. Does NOT merge, push, or run AI
review (use `/dg` for that).

Destination: `feature/* fix/* refactor/* test/* docs/* chore/*` → `{INTEGRATION_BRANCH}`;
`hotfix/*` → `main`; anything else → ask. Compare with `git diff <dest>...HEAD`.

## Checks (adapt the stack-specific ones to the project's `{TEST_COMMANDS}`)

0. **Destination merged in** — `git log HEAD..<dest> --oneline` must be empty; if not,
   STOP (results on a stale branch are unreliable) and tell the user to merge first.
1. **Backend/primary test suite** — run it; show the summary line.
2. **Frontend/secondary test suite** — if the project has one.
3. **E2E suite** — if the project has one and the branch touches runtime behavior.
   Two worktree traps: the servers under test must serve the **branch's** code
   (long-running dev servers usually serve the main checkout, not the worktree), and
   non-idempotent seeded fixtures must be reseeded first. Skipping is allowed for a
   docs-only branch or known-baseline failures, but must be reported as
   `WAIVED: <reason>` — never silent.
4. **Type check** — e.g. `tsc --noEmit`, `mypy`; show errors in full.
5. **Lint check (error level)** — e.g. `eslint`, `ruff check`. Type checkers do not
    catch lint findings, so an ungated linter's error debt silently creeps back
    between cleanups. Gate only suites the project keeps at zero errors; report
    known-debt suites explicitly instead of failing on them.
6. **Secrets scan** — run the guard's own patterns over the added lines of
   `git diff <dest>...HEAD`. Read them at run time from the first of
   `${CLAUDE_PLUGIN_ROOT}/hooks/agent/pre-commit-check.sh`, `.ai/hooks/agent/pre-commit-check.sh`,
   `hooks/agent/pre-commit-check.sh` that exists (the `hit '…'` lines, the `.env` rule,
   the credential-literal grep); if none does, ❌ "guard not found" — never report a
   scan you could not run. Apply **no exemptions** here: the guard skips prose files
   and honours `flight-rules: allow` at commit time; the branch-level scan is the
   second look, so it reports those too, as ⚠️. ❌ on any other hit (redact values).
7. **Debug-logging check** — new `console.log` / stray print/debug lines: ⚠️ warn.
8. **Conventional commits** — every commit on the branch starts with an allowed prefix
   (`feature:` `fix:` `refactor:` `test:` `docs:` `chore:`; `hotfix/` branches use `fix:`).
9. **Single-purpose scope** — commits describe one coherent concern; ⚠️ if clearly not.
10. **Merge-conflict markers** — none added in the diff.
11. **Dependency audits** — `npm audit --audit-level=high` / `pip-audit` (or the
    ecosystem's equivalent). ❌ on new high/critical introduced by this branch;
    ⚠️ + explicit note for pre-existing findings on the destination.
12. **No untracked env/secret files** staged or appearing.
13. **Tests accompany source changes** — source files changed without a test change:
    ⚠️ list them.
14. **Migrations present if models/schema changed** — ⚠️ if not.
15. **New TODO/FIXME/HACK** — ⚠️ list; resolve or track before merge.
16. **Commit-count sanity** — ⚠️ above ~20 commits: consider splitting.
17. **Docs match the change** — grep the docs (`README*`, `docs/`, `rules/`, `skills/`,
    script header comments) for every name the diff renames or removes. ❌ if a doc
    still describes the old behaviour; ⚠️ if a behaviour change touched no doc and the
    PR does not say why.

## Report

Numbered ✅/⚠️/❌ summary table, then:
- Any ❌ → `Result: NOT READY` — do NOT stamp.
- Clean → `Result: ✅ READY TO MERGE` and stamp:
  ```bash
  git notes --ref=pre-merge-check add -f -m "passed: $(date -u +%Y-%m-%dT%H:%M:%SZ) branch:$(git branch --show-current)" HEAD
  ```

Always end with: this command does not merge or push; warnings are non-blocking but
must be acknowledged; run `/dg` for adversarial review of code changes; merging needs
explicit user confirmation.
