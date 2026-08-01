# Hooks

Enforcement for the worktree workflow — the rules stop being advisory when these are
installed. Two kinds, deliberately separated:

| Directory | Kind | Runs on | Tool-specific? |
|---|---|---|---|
| `git/` | git hooks | git itself (`core.hooksPath`) | No — pure git |
| `agent/` | assistant-event hook scripts | the AI assistant's hook events | Logic is generic; the I/O protocol is per-tool (currently Claude Code) |

**`agent/pre-commit-check.sh` is plugin-activated.** Installing or updating the
flight-rules plugin registers it as a `PreToolUse` hook — no copying, no wiring. It was
a copy-in template only while its branch list had to be edited into the script; now
that the list has safe defaults and reads `.ai/flight-rules.conf`, the plugin ships it
live. A project consuming it this way should **delete any local fork**, or the guard
runs twice.

⚠️ That means **installing the plugin starts blocking commits on `main`**. If a project
does not want that, opt out rather than uninstalling:

```ini
# .ai/flight-rules.conf
PROTECTED_BRANCHES=off
```

The secret scan keeps running when the branch policy is off — leaking a key is not a
workflow preference.

The **git hooks in `git/`** are still **templates to copy**: git finds them through
`core.hooksPath`, which no plugin can set on your behalf. Copy them to `.ai/hooks/`,
run `install.sh`, and edit their parameter variables in place — git runs them outside
the assistant, so they see neither `settings.json` nor (yet) the conf file.

## Git hooks (`git/`)

- **`pre-merge-commit`** — mechanism 1 of the merge gate: **PR-only branches**
  (`PR_ONLY_BRANCHES`, default `main`) are blocked from any local merge; they move
  only through a reviewed pull request. The hook fires only when git creates a merge
  commit (a `--ff-only` pull does not), so its firing on a PR-only branch *is* the
  violation — robust, and needs no `MERGE_HEAD`. Sync with
  `git pull --ff-only origin main`.
- **`commit-msg`** — mechanism 2: **note-gated branches** (`NOTE_GATED_BRANCHES`,
  default `dev`/`staging`) require a passing `pre-merge-check` note on the incoming
  commit. This check used to live in `pre-merge-commit` and was a **silent no-op**:
  modern git (verified on 2.55) writes `MERGE_HEAD` *after* that hook runs, so the
  lookup never found the incoming commit and nothing was ever enforced. `commit-msg`
  runs with `MERGE_HEAD` present. A non-merge commit exits immediately — this gates
  merges, never ordinary commits. **Install both hooks**, or the gate is half built;
  `install.sh` fails loudly if `commit-msg` is missing.
  Tests: `merge-gate.test.sh` (no arguments, no network).
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

`pre-commit-check.sh` is configured per project **without forking it**. The primary
home is `.ai/flight-rules.conf` — beside the rules, not inside any one tool's settings
— so a git hook, a Claude Code hook and another assistant's adapter all read one list
instead of each restating it:

```ini
# .ai/flight-rules.conf
PROTECTED_BRANCHES=^(main|release/.*)$
WORKTREE_DIR=.worktrees
```

The file is parsed as **data** (matched with `sed`, never `source`d), so a cloned
repository cannot execute code through it. `#` comments, blank lines, spaces around
`=`, and quoted values are all fine.

| Setting | `.ai/flight-rules.conf` key | Environment variable | Controls |
|---|---|---|---|
| Protected branches | `PROTECTED_BRANCHES` | `FLIGHT_RULES_PROTECTED_BRANCHES` | Branches the guard defends. A POSIX ERE matched **case-insensitively** — anchor it with `^`/`$`. |
| Worktree path | `WORKTREE_DIR` | `FLIGHT_RULES_WORKTREE_DIR` | Path suggested in the block message. Default `.ai/worktrees`. |

Resolution order is **environment → `.ai/flight-rules.conf` → built-in default**, and
the conf file is read from the repo the command targets, so a session spanning several
repos gets each project's own policy. The environment variables carry a
`FLIGHT_RULES_` prefix because the environment is a shared namespace; the file keys do
not, because the filename already scopes them.

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

- **`.ai/flight-rules.conf`** (recommended) — tool-agnostic and committed with the
  project, so every assistant and every contributor gets the same policy. This is the
  one to use.
- **`.claude/settings.json` `"env"`** — a Claude-Code-only override, for when a policy
  should apply to Claude sessions but not to the git hooks.
- **The shell environment** — `export FLIGHT_RULES_PROTECTED_BRANCHES='^main$'`. Useful
  for a one-off; not durable.

The hook does **not** read a `.env` file. If your project keeps settings there, put the
branch policy in `.ai/flight-rules.conf` instead — `.env` is for secrets and
per-machine values, and this policy is neither.

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
