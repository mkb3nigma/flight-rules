# Hooks

Enforcement for the worktree workflow — the rules stop being advisory when these are
installed. Two kinds, deliberately separated:

| Directory | Kind | Runs on | Tool-specific? |
|---|---|---|---|
| `git/` | git hooks | git itself (`core.hooksPath`) | No — pure git |
| `agent/` | assistant-event hook scripts | the AI assistant's hook events | Logic is generic; the I/O protocol is per-tool (currently Claude Code) |

These are **templates to copy into a project**, not plugin-activated hooks — nothing
here fires just by installing the flight-rules plugin. Copy them into the project
(recommended home: `.ai/hooks/` for the git hooks, `.ai/hooks/agent/` for the agent
scripts) and commit them.

Branch names differ per project, so `pre-commit-check.sh` reads its settings from the
**environment** rather than requiring you to edit the script — see
[Configuration](#configuration). Fork it only to change its logic, not its branch list.
The git hooks in `git/` still need their parameter variables edited in place: git runs
them directly, so they never see a `.claude/settings.json` `env` block.

## Git hooks (`git/`)

- **`pre-merge-commit`** — the merge gate, two mechanisms:
  - **PR-only branches** (`PR_ONLY_RE`, default `main`) are blocked from any local
    merge — they move only through a reviewed pull request. The hook fires only when
    git creates a merge commit (a `--ff-only` pull does not), so its firing on a
    PR-only branch is the violation; robust, needs no `MERGE_HEAD`. Sync with
    `git pull --ff-only origin main`.
  - **Note-gated branches** (`PROTECTED_RE`, e.g. `dev`/`staging`) require a passing
    `pre-merge-check` note on the incoming commit. ⚠️ **Known bug (tracked):** modern
    git writes `MERGE_HEAD` *after* `pre-merge-commit` runs (verified on git 2.55), so
    this mechanism is currently a **no-op** — the note is never read. Repair = relocate
    the check to `commit-msg`, where `MERGE_HEAD` exists. Until then only mechanism 1
    (PR-only) actually enforces.
- **`post-merge`** — after a merge into the integration branch, writes a cleanup note
  (stale worktrees, deletable branches) that the next AI session picks up.
  Optionally (`CLEAR_AI_CONTEXT=1`, off by default) also clears Claude Code's stored
  conversations for the project so the next session starts fresh — read the guarded
  block in the script before enabling.
- **`install.sh`** — one-time per clone: `chmod` the hooks, set
  `core.hooksPath`, and set `merge.ff false` so the merge gate always fires
  (a fast-forward merge would silently skip `pre-merge-commit`).

## Agent hook scripts (`agent/`)

Guards that fire on the assistant's own events, before git ever runs:

- **`pre-commit-check.sh`** — PreToolUse guard on the Bash tool. On a protected branch
  it denies both `git commit` **and** the working-tree destroyers that would otherwise
  slip past it — `git rm`, `git reset --hard`, `git clean -f`, `git checkout -- .`,
  `git restore`. (Gating on `git commit` alone is porous: those commands do their damage
  without any commit following, so the guard never sees them.) A merge in progress is
  exempt, since resolving conflicts on the integration branch legitimately needs them.
  Independently of branch, it denies commits with staged `.env` files, cloud/API key
  patterns, private-key headers, or hardcoded credential literals.
  Tests: `pre-commit-check.test.sh` (`./pre-commit-check.test.sh` — no arguments, no
  network, builds throwaway repos).
- **`session-start.sh`** — SessionStart banner: once a day, lists worktrees whose
  branches are already merged so they get cleaned up.

### Configuration

`pre-commit-check.sh` takes its project settings from environment variables, so a
project can retune it without forking. Set them in the consuming project's
`.claude/settings.json`:

```json
{
  "env": {
    "FLIGHT_RULES_PROTECTED_BRANCHES": "^(main|release/.*)$",
    "FLIGHT_RULES_WORKTREE_DIR": ".worktrees"
  }
}
```

| Variable | Controls |
|---|---|
| `FLIGHT_RULES_PROTECTED_BRANCHES` | Branches the guard defends. A POSIX ERE matched **case-insensitively** against the branch name — anchor it with `^`/`$`. |
| `FLIGHT_RULES_WORKTREE_DIR` | Path suggested in the block message. Default `.ai/worktrees`. |

**Default protected set** — `main`, `master`, `dev`, `develop`, `development`,
`staging`, `stage`, `qa`, `uat`, `prod`, `production`, and `release` (bare or as a
`release/1.0` train). Case-insensitive, so `QA` and `qa` are the same branch here.

The default is broad on purpose: being stopped on a branch you did not mean to protect
costs one message, while *not* being stopped on one you did costs work. It covers the
common conventions (git-flow's `develop`, release trains, QA/UAT gates) so most projects
need no configuration at all. `hotfix/*` is deliberately excluded — you commit to a
hotfix branch, so it is a working branch, not one to defend.

> ⚠️ **The variable replaces the default list — it does not extend it.** Setting
> `FLIGHT_RULES_PROTECTED_BRANCHES` to `^integration$` protects that branch and
> *nothing else*: `main` and `dev` become unguarded. To keep the defaults **and** add
> your own, copy the whole pattern and extend the first group.

Worked examples:

| Goal | Value |
|---|---|
| Only `main` | `^main$` |
| `main` plus release trains | `^(main\|release/.*)$` |
| Trunk-based, one branch | `^trunk$` |
| Defaults **plus** `integration` | `^(main\|master\|dev\|develop\|development\|staging\|stage\|qa\|uat\|prod\|production\|integration)$\|^release(/\|$)` |

### Where to set it

Two places work, and they resolve in this order:

1. **`.claude/settings.json` `"env"`** (recommended) — committed with the project, so
   every session and every contributor gets the same policy.
2. **The shell environment** — `export FLIGHT_RULES_PROTECTED_BRANCHES='^main$'` before
   launching the assistant. Useful for a one-off; not durable.

The hook reads plain environment variables, so anything that ends up in the assistant's
environment works. Note it does **not** load a `.env` file itself — if your project keeps
these in `.env`, source it in your shell first, or mirror the value into
`.claude/settings.json`, which is the reliable path.

Settings come from the environment and never from a file inside the repository: a
sourced config file would let any cloned repo execute code inside the hook.

### Wiring (Claude Code)

Keep the scripts in `.ai/hooks/agent/` and point `.claude/settings.json` at them:

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command",
      "command": "bash -c 'exec \"$(git rev-parse --show-toplevel)/.ai/hooks/agent/session-start.sh\"'" }] }],
    "PreToolUse": [{ "matcher": "Bash", "hooks": [{ "type": "command",
      "command": "bash -c 'exec \"$(git rev-parse --show-toplevel)/.ai/hooks/agent/pre-commit-check.sh\"'" }] }]
  }
}
```

(Equivalently, `.claude/hooks/*.sh` can be two-line shims that `exec` the `.ai`
scripts — useful when migrating an existing setup without touching settings.json.)

The scripts read Claude Code's hook protocol — tool input as JSON on stdin, a
structured `permissionDecision` on stdout. To use them with another assistant, wrap
the same checks in that tool's hook protocol; the point of keeping them in `.ai/` is
that the logic has exactly one home.

## Layered defence

The agent guard and the git gate overlap on purpose: `pre-commit-check.sh` stops the
assistant *before* it runs a bad commit, and `pre-merge-commit` stops *anyone* (human
or tool that bypassed the agent layer) at merge time. Keep both.
