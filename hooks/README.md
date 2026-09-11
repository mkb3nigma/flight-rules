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
  violation, and it needs no `MERGE_HEAD`. It only sees merges git completes in one
  step: a **conflicted** merge stops before the merge commit and never reaches this
  hook, which is why `reference-transaction` below is the actual guarantee and this
  is the early, specific message. Sync with `git pull --ff-only origin main`.
- **`commit-msg`** — mechanism 2: **note-gated branches** (`NOTE_GATED_BRANCHES`; unset,
  the set is *protected but not PR-only*) require a passing `pre-merge-check` note on the
  incoming commit. This check used to live in `pre-merge-commit` and was a **silent no-op**:
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
  **A passing note is not consent.** The agent writes that note itself, so a stamped
  merge nobody asked for used to land with a green `✅ Pre-merge check verified` —
  measured 2026-09-10, no warning of any kind. The merge is now refused unless it says
  who wanted it: `FLIGHT_RULES_MERGE_AUTHORISED=1 git merge …`. An agent *can* set that
  variable itself — nothing inside its own tool calls distinguishes "the user asked"
  from "the agent decided" — so this does not claim proof. It makes the unbidden merge
  a deliberate, named act rather than a silent one, and writes the outcome into the
  merge commit as a `Merge-authorisation:` trailer, which survives and is greppable.
  `MERGE_NEEDS_INSTRUCTION=off` drops the check; that is recorded in the trailer too,
  so history still distinguishes the two.
  Tests: `merge-gate.test.sh` (no arguments, no network).
- **`pre-rebase`** — refuses to rebase a PR-only branch: `git rebase feature` on
  `main` rewrites it with no merge commit, so nothing else fires.
- **`reference-transaction`** — the backstop for everything that moves a REF, and the
  only hook that sees every one of those. One rule: **a PR-only branch may only move to
  a commit already on `origin/<branch>`.**
  Read the scope precisely: it fires when a ref moves. `git rm`, `git clean -fd`,
  `git restore`, `git checkout -- .` and `git stash drop` destroy work and move no ref,
  so **this hook never sees them** — the agent guard is the only thing between an agent
  and that class. Verified 2026-09-11 on a repo with the full gate installed: a commit on
  `main` was blocked and the ref held, while `git rm`, `git clean -fd` and
  `git stash drop` all succeeded and destroyed their target. An earlier wording here
  ("the only hook that sees every write path") read as though it covered them; it does
  not, and a change was built on that misreading before the error was caught. It asks where the ref landed, not which command moved it, so
  the enumeration cannot fall behind. It exists because the command-shaped guards kept
  losing (all verified on git 2.55, 2026-09-10):
  `git cherry-pick` and `git revert` run **neither** `pre-commit` nor `commit-msg` —
  they are sequencer operations and fire only `prepare-commit-msg`; `git branch -f`
  and `git update-ref` create no commit, so no commit hook fires at all; and a
  **conflicted** `git merge` never reaches `pre-merge-commit`, because git stops at the
  conflict and the finishing `git commit` is an ordinary commit. Every one of those
  reached `main` unguarded before this hook.
  `git pull --ff-only`, all feature work, `fetch`, and branch creation are unaffected.
  Unlike the agent guard it reads its config from the **upstream's** committed state,
  so editing the working-tree conf — the bypass the agent guard's own block message
  advertises — does not lift it. A repo with no upstream is not gated: there is no
  reviewed state to compare against, and a fresh `git init` must stay usable.
  Tests: `ref-gate.test.sh` (no arguments, no network).
  **Install all of `hooks/git/`**, or the gate is half built; `install.sh` refuses
  unless all five bare-named hooks are present.
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
  `+refspec`, `--delete`, `origin :main`, `--mirror`); a push that names some other
  ref is judged on that ref, not on the branch you happen to stand on, so post-merge
  cleanup from the protected branch is not blocked. It also denies `git branch -d`/`-D`
  of a protected branch — local deletion, which `post-merge` was found recommending.
  A matcher's trailing boundary is an **end-of-token**, not a space: a subshell closes
  with `)`, a brace group or loop body with `;`. Until 2026-09-10 it was `[[:space:]]`
  alone, so `git rebase`, `git push --mirror`, `git switch -f`, `git stash drop|clear`,
  `git checkout --` and `git restore` were each denied bare and **allowed** inside
  `( … )` or `{ …; }` on a protected branch.
  **Targets are read per simple command**, not per command string: a greedy match found
  only the last `git push`/`git branch` in a compound, so a protected target in an
  earlier one escaped (`git branch -d main && git branch -d feature/x` was allowed), and reading
  past the end of that command turned a later word into a target (a following
  `echo main` refused the deletion of a feature branch). Both fixed 2026-09-10. On **any** branch of the project
  it denies `git checkout -b`/`-B` and `git switch -c`/`--create` — branches are
  created as worktrees (workflow rule 6), and the block shows the command. "The
  project" is its main checkout *and every worktree of it* — they share one
  `--git-common-dir`, which is how a worktree is told from an unrelated repo whose
  branches are none of this project's business.
  `git -C`/`-c` are normalised
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
| Note-gated branches | `NOTE_GATED_BRANCHES` | `FLIGHT_RULES_NOTE_GATED_BRANCHES` | `commit-msg` | Merging in needs a passing `pre-merge-check` note. **No default names**: unset, the gated set is *protected but not PR-only*, so a project gets the gate on whatever it calls its branches. Set it to override, or to `off`. |
| Merge needs instruction | `MERGE_NEEDS_INSTRUCTION` | `FLIGHT_RULES_MERGE_AUTHORISED` (per-merge) | `commit-msg` | A merge into a protected branch is refused unless `FLIGHT_RULES_MERGE_AUTHORISED=1` is set on that merge. Default on. Set to `off` to drop the check. Either way the merge commit gets a `Merge-authorisation:` trailer. |
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

**With the plugin, nothing to wire** — `hooks/hooks.json` registers all three agent
hooks; pointing `settings.json` at a copy too runs the guard twice. **Without it**, keep
the scripts in `.ai/hooks/` and point `.claude/settings.json` at them:

There are **three**, and each path used to ship a different two. Until 2026-09-10 the
plugin registered the principles injector and the guard but not `session-start.sh`, so
plugin users got no install health check; the snippet below registered
`session-start.sh` and the guard but not the injector, so hand-wired users got **no
rules injected at all** — half of what this playbook does. Register all three.

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [
      { "type": "command",
        "command": "bash -c 'exec \"$(git rev-parse --show-toplevel)/.ai/hooks/session-start-rules.sh\"'" },
      { "type": "command",
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

### The agent guard over-blocks prose. That is the accepted trade.

It matches a git verb anywhere in the command string, so writing *about* a git command
can read as running one — `echo "never git rm on main" >> notes.md` is refused. In a
repo whose product is documentation about git, that is not rare.

Measured 2026-09-11 against 405 commands taken from real sessions:

| Standing on | Denied | False positives |
|---|---|---|
| a feature branch | 6 / 405 | **0** — all six correct (`checkout -b`, force-push to `main`) |
| a protected branch | 25 / 405 (6.2%) | 15, all prose; none contained a destructive git command |

The exposure is confined to a protected branch, which the worktree workflow keeps you off
except for sync, cleanup and docs.

**Fixing it was attempted and rejected.** Matching only in "command position" requires
knowing what is inside quotes, which a regex cannot tell: the attempt allowed
`git commit -am "feat: add -h shorthand"` — an unwrapped commit on `main` — because a
quoted `-h` disarmed every matcher, and three more bypasses besides. Each failed *open*.
A pure-bash shell lexer would fix those particular cases and leave the shape: a hand-made
approximation of shell parsing whose gaps resolve to "allow".

So the guard stays strict. A false positive costs a turn. A false negative costs a file
with nothing behind it — per the scope note above, the ref gate does not catch that class.
Anyone revisiting this needs a rule the attempt lacked: **every uncertainty resolves
toward deny** — an unrecognised construct keeps the strict behaviour rather than skipping
the check.

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
