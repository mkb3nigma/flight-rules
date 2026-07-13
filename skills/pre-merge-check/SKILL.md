---
name: pre-merge-check
description: Run the automated pre-merge checklist for the current feature branch. No AI review — safe to run repeatedly. Stamps a git note the merge-guard hook can verify.
---

# /pre-merge-check — Automated Pre-Merge Checklist

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
   Skipping (docs-only branch, known-baseline failures) must be reported explicitly,
   never silent.
4. **Type check** — e.g. `tsc --noEmit`, `mypy`; show errors in full.
5. **Secrets scan** — grep the diff for cloud keys (`AKIA[A-Z0-9]{16}`), API-key
   literals (`sk-[a-zA-Z0-9]{32,}`), private-key headers, and hardcoded
   `password/secret/token/api_key = "<literal>"`. ❌ on any hit (redact values).
6. **Debug-logging check** — new `console.log` / stray print/debug lines: ⚠️ warn.
7. **Conventional commits** — every commit on the branch starts with an allowed prefix.
8. **Single-purpose scope** — commits describe one coherent concern; ⚠️ if clearly not.
9. **Merge-conflict markers** — none added in the diff.
10. **Dependency audits** — `npm audit --audit-level=high` / `pip-audit` (or the
    ecosystem's equivalent). ❌ on new high/critical introduced by this branch;
    ⚠️ + explicit note for pre-existing findings on the destination.
11. **No untracked env/secret files** staged or appearing.
12. **Tests accompany source changes** — source files changed without a test change:
    ⚠️ list them.
13. **Migrations present if models/schema changed** — ⚠️ if not.
14. **New TODO/FIXME/HACK** — ⚠️ list; resolve or track before merge.
15. **Commit-count sanity** — ⚠️ above ~20 commits: consider splitting.

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
