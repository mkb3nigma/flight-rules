# Hooks

Enforcement for the worktree workflow — the rules stop being advisory when these are
installed. Two kinds, deliberately separated:

| Directory | Kind | Runs on | Tool-specific? |
|---|---|---|---|
| `git/` | git hooks | git itself (`core.hooksPath`) | No — pure git |
| `agent/` | assistant-event hook scripts | the AI assistant's hook events | Logic is generic; the I/O protocol is per-tool (currently Claude Code) |

These are **templates to copy into a project**, not plugin-activated hooks — every
project sets its own protected branches, so nothing here activates just by installing
the flight-rules plugin. Copy them into the project (recommended home: `.ai/hooks/`
for the git hooks, `.ai/hooks/agent/` for the agent scripts), adjust the parameter
variables at the top of each script, and commit them.

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

- **`pre-commit-check.sh`** — PreToolUse guard on the Bash tool: denies `git commit`
  on a protected branch (worktrees only) and denies commits with staged `.env` files,
  cloud/API key patterns, private-key headers, or hardcoded credential literals.
- **`session-start.sh`** — SessionStart banner: once a day, lists worktrees whose
  branches are already merged so they get cleaned up.

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
