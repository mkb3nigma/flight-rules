# flight-rules — working in this repo

This is the playbook itself, so it follows its own rules. Read `rules/` — every file,
they are short — and treat them as binding here: `engineering-principles.md` for how
to make a change, `git-worktree-workflow.md` for branching. The SessionStart hook
injects the principles; the rest you read once.

## Parameters

`.ai/flight-rules.conf` is the single home for the branch policy. Summary:

| Parameter | Value |
|---|---|
| `{PROTECTED_BRANCHES}` / `{PR_ONLY_BRANCHES}` | `main` — no direct commits, no local merges; it moves only through a reviewed PR |
| `{INTEGRATION_BRANCH}` | `main` (trunk-based; there is no `dev`) |
| `{WORKTREE_DIR}` | `.ai/worktrees/` (git-ignored) |
| `{TEST_COMMANDS}` | `hooks/agent/pre-commit-check.test.sh`, `hooks/git/merge-gate.test.sh`, `hooks/doctor.test.sh`, `skills/catalogue.test.sh` — no arguments, no network |

Every change: `git fetch origin`, `git worktree add .ai/worktrees/<slug> -b <prefix>/<slug> origin/main`,
commit there, push, `gh pr create --base main`. Never commit on `main`; never merge
into it locally. Sync with `git pull --ff-only origin main`.

## The skills run here too

`.claude/skills/<name>/SKILL.md` are three-line pointers at `skills/<name>/SKILL.md`,
so `/pre-merge-check`, `/pr-create`, `/commit` and the rest work in this repo without
the plugin (which would register the guard twice). Use them on your own changes.

## Enforcement runs from `hooks/`, not from a copy

The hooks this repo ships are the hooks it runs — `.claude/settings.json` points at
`hooks/agent/`, and `core.hooksPath` is set to `hooks/git` once per clone:

```bash
git config core.hooksPath hooks/git && git config merge.ff false
```

There is deliberately no `.ai/hooks/` copy: a copy drifted once (it was the pre-conf,
commit-only guard for weeks) and the rules repo cannot afford to run stale rules on
itself. If a change to a hook needs a matching change to what this repo runs, it
happens in the same commit, because they are the same file.

## When editing a hook

- Run both suites before and after; add a case for every gap you close. A guard that
  silently stops matching is worse than none — the tests exist to make that loud.
- Verify against the running hook, not by reading the regex. Several past gaps were
  invisible on paper (column-zero secrets, `git -C … commit`, macOS `grep -P`).
- macOS ships BSD `grep`, `sed` and bash 3.2. CI runs the suites on both macOS and
  Ubuntu; do not use `grep -P`, `mapfile`, or `sed -i` without a suffix.
- Bump `.claude-plugin/plugin.json` when hook behaviour changes.
