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

The **git hooks in `git/`** are still **files to copy**: git finds them through
`core.hooksPath`, which no plugin can set for you. Copy them to `.ai/hooks/` and run
`install.sh`. No editing — they read their branches from `.ai/flight-rules.conf`, the
one channel git hooks, agent hooks and skills all share.

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
  merges, never ordinary commits. A **back-merge** — the incoming commit is the tip of
  a PR-only branch — passes without a note: it already went through a reviewed PR, and
  reconciling `main` into the integration branch is what `feature-start` step 4 asks
  for. Only local branches and `origin/*` count, and the commit must be on `origin/<x>`
  when origin has it — a forced local `main` or a stale `upstream/main` exempts nothing.
  The same hook refuses the commit that would complete a **squash merge** into a
  PR-only branch, which creates no merge commit and so never fires `pre-merge-commit`.
  Tests: `merge-gate.test.sh` (no arguments, no network).
- **`pre-rebase`** — refuses to rebase a PR-only branch: `git rebase feature` on
  `main` rewrites it with no merge commit, so nothing else fires.
  **Install all of `hooks/git/`**, or the gate is half built; `install.sh` refuses
  unless all four bare-named hooks are present.
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
  it denies `git commit` and everything that rewrites or discards the tree without one:
  `rm`, `restore`, `reset --hard|--merge`, `clean -f`, `checkout -- .` and
  `checkout <rev> -- <path>`, `switch --discard-changes`, `rebase` (not its
  `--abort`/`--continue`), `stash drop|clear`. From any branch it denies a push that
  force-updates, deletes or mirrors over a protected branch (`-f`, `--force*`,
  `+refspec`, `--delete`, `origin :main`, `--mirror`). `git -C`/`-c` are normalised
  away first, the *last* `cd` decides the target repo, and a merge in progress is
  exempt so conflicts can be resolved.
  Regardless of branch, a commit is denied with a staged `.env` (templates
  `.env.example|sample|template|dist` and `.env.md` exempt), a provider key (AWS,
  `sk-…`, GitHub, Slack, Google), any PEM private-key header, or a credential literal
  outside test and prose files (`docs/`, `locales/`, `i18n/`, `translations/`,
  `*.md|rst|txt` — keys are still caught
  there). A line marked `flight-rules: allow` is a reviewed exception.
  Needs `jq` or `python3`; with neither it denies git commands with an install hint
  rather than silently switching off.
  Tests: `pre-commit-check.test.sh` (no arguments, no network).
- **`doctor.sh`** — is the enforcement actually installed? Checks `core.hooksPath`,
  every hook's executable bit, `merge.ff`, the guard's parser, the conf's keys and
  regexes, and that the guard is wired once — every one a state that has failed
  silently before. `session-start.sh` runs it daily and prints only problems.
  Tests: `doctor.test.sh`.
- **`session-start.sh`** — SessionStart banner: once a day per project, lists
  worktrees whose branches are already merged so they get cleaned up. Reads
  `INTEGRATION_BRANCH` and `WORKTREE_DIR` from `.ai/flight-rules.conf` when present.

### Configuration

Every hook is configured per project **without forking it**, from
`.ai/flight-rules.conf` — beside the rules, not inside any one tool's settings, so
every layer reads one list:

```ini
# .ai/flight-rules.conf
PROTECTED_BRANCHES=^(main|release/.*)$
WORKTREE_DIR=.worktrees
```

The file is parsed as **data** (matched with `sed`, never `source`d), so a cloned
repository cannot execute code through it. `#` comments, blank lines, spaces around
`=`, and quoted values are all fine.

| Setting | conf key | Environment variable | Read by | Controls |
|---|---|---|---|---|
| Protected branches | `PROTECTED_BRANCHES` | `FLIGHT_RULES_PROTECTED_BRANCHES` | agent guard | Branches the guard defends. POSIX ERE, matched case-insensitively — anchor it. `off` disables the branch policy (secret scan stays on). |
| PR-only branches | `PR_ONLY_BRANCHES` | `FLIGHT_RULES_PR_ONLY_BRANCHES` | git hooks | No local merge or rebase; moves only through a PR. Default `^main$`. |
| Note-gated branches | `NOTE_GATED_BRANCHES` | `FLIGHT_RULES_NOTE_GATED_BRANCHES` | `commit-msg` | Merging in needs a passing `pre-merge-check` note. Default `^(dev\|staging)$`. |
| Integration branch | `INTEGRATION_BRANCH` | — | `post-merge`, `session-start.sh`, skills | Where features merge. Default `main` everywhere. |
| Worktree path | `WORKTREE_DIR` | `FLIGHT_RULES_WORKTREE_DIR` | agent guard, `session-start.sh`, skills | Where worktrees live; suggested in the block message. Default `.ai/worktrees`. |

Resolution order is **environment → `.ai/flight-rules.conf` → built-in default**, and
the conf file is read from the repo the command targets, so a session spanning several
repos gets each project's own policy.

> ⚠️ **The two git hooks read the conf from `HEAD`, not the working tree.** During a
> merge git updates the working tree *before* the hooks run, so a working-tree read
> would let the incoming branch configure the gate that judges it — a branch shipping
> `NOTE_GATED_BRANCHES=^nothing$` would wave itself through. They read
> `HEAD:.ai/flight-rules.conf` (the merge target's committed policy) and fall back to
> the built-in default, never to the working tree. Practical consequence: **a conf
> change only takes effect on the merge gate once it is committed on the target
> branch.** `pre-commit-check.sh` still reads the working tree on purpose — it guards
> an interactive session, where an uncommitted edit should apply immediately.

The environment variables carry a `FLIGHT_RULES_` prefix because the environment is a
shared namespace; the file keys do not, because the filename already scopes them.

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

The conf file is read as data and never `source`d: a sourced config file would let any
cloned repo execute code inside the hook.

### Wiring (Claude Code)

**With the plugin, nothing to wire** — `hooks/hooks.json` registers both agent hooks;
pointing `settings.json` at a copy too runs the guard twice. **Without it**, keep the
scripts in `.ai/hooks/agent/` and point `.claude/settings.json` at them:

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

## What these hooks are — and are not

**They are guardrails against mistakes, not security controls.** Every one is trivially
bypassable by someone who means to: `git commit --no-verify`, `git merge --no-verify`,
editing the hook script, or repointing `core.hooksPath`. That is unavoidable — the
hooks live in a repository their user controls, and any design that "fixed" it would
break the requirement that they work for anyone who clones without the plugin.

This is deliberate, because the failures worth preventing are the accidental ones:

- committing to `dev` out of habit, in the wrong terminal tab
- merging a branch whose checks were never run
- a `git rm` issued with a relative path after a `cd` silently failed
- an assistant taking a shortcut past a block it does not understand

Known blind spots, by the same logic: a git alias (`git ci`) and `$(which git) rm`.
Neither happens by accident.

**The design rule follows: close the paths reachable by accident; do not contort the
design to stop someone acting deliberately.** A guard that catches the careless case
and is honest about the willful one is more useful than one that poses as a security
boundary and isn't.

That rule settles real trade-offs. When the merge gate turned out to read its config
from the working tree — letting an incoming branch relax the rule judging it — the
config route was closed, because changing one line of config is something that happens
by accident, or that an agent does to get unblocked. The *other* route to the same
outcome, rewriting the hook script itself, was left open: it is conspicuous, it would
stand out in review, and closing it would mean moving the hooks out of the repo. Same
outcome, very different odds of being reached by accident, and only one of them worth
engineering against.

## Layered defence

The agent guard and the git gate overlap on purpose: `pre-commit-check.sh` stops the
assistant *before* it runs a bad commit, and `pre-merge-commit` stops *anyone* (human
or tool that bypassed the agent layer) at merge time. Keep both.
