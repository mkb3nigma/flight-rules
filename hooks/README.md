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

`off` is wider than it looks in one direction and narrower in another. It also stops
`checkout -b`/`switch -c` being denied, and — when `NOTE_GATED_BRANCHES` is unset —
silences the note gate, because the gated set is derived as *protected but not PR-only*
and with no protected branches that set is empty. A project with a `dev` branch loses its
`pre-merge-check` gate without being told; name `NOTE_GATED_BRANCHES` explicitly to keep
it. What it does **not** touch is the PR-only side: `pre-merge-commit`, `pre-rebase` and
the squash guard read `PR_ONLY_BRANCHES` directly, so local merges and rebases into a
PR-only branch stay refused.

What `off` does **not** turn off is the secret scan — leaking a key is not a workflow
preference.

The **git hooks in `git/`** are still **files to copy**: git finds them through
`core.hooksPath`, which no plugin can set for you. Copy them to `.ai/hooks/` and run
`install.sh`. No editing — they read their branches from `.ai/flight-rules.conf`, the
one channel git hooks, agent hooks and skills all share.

> **What these are for.** They catch the workflow slip — a fix committed straight to a
> protected branch, a merge of work whose checks never ran, a `git rm` with a relative
> path after a `cd` that silently failed. They are guardrails, not a security boundary:
> anyone who means to get past them can, and an assistant given full control of a machine
> is beyond anything a repository of rules can reach. The goal is to make the accidental
> path harder than the correct one. The full statement, with what is deliberately left
> uncovered, is in [What these hooks are — and are not](#what-these-hooks-are--and-are-not).

## Contents

- [Configuration](#configuration)
  - [Where to set it](#where-to-set-it)
- [Wiring (Claude Code)](#wiring-claude-code)
- [Git hooks (`git/`)](#git-hooks-git)
- [Agent hook scripts (`agent/`)](#agent-hook-scripts-agent)
- [What these hooks are — and are not](#what-these-hooks-are--and-are-not)
  - [With the plugin alone, a protected branch is only half guarded](#with-the-plugin-alone-a-protected-branch-is-only-half-guarded)
  - [The agent guard over-blocks prose. That is the accepted trade.](#the-agent-guard-over-blocks-prose-that-is-the-accepted-trade)
- [Layered defence](#layered-defence)

Installing is above. The first three sections configure and wire the hooks; the next
two are the reference, one entry per hook. **What these hooks are — and are not** is
what they do **not** catch — measured rather than asserted — and is worth reading
before you rely on them.

## Configuration

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
`=`, and quoted values are all fine — including a comment **after** a value
(`PROTECTED_BRANCHES=^main$   # trunk-based`). An inline comment must be preceded by
whitespace, so a `#` inside a value (`^feature#1$`) is kept.

That last part was a documented claim before it was a true one. Until 2026-09-11 the
three hook parsers captured to end-of-line, so a trailing comment became part of the
regex, the value matched nothing, and the layer reading it stopped enforcing in silence
— while `flight-rules-doctor.sh`, which *did* strip comments, printed ✅ for the same line. One
trailing comment on `PR_ONLY_BRANCHES` let a direct commit land on a PR-only `main`
with all five git hooks installed.

| Setting | conf key | Environment variable | Read by | Controls |
|---|---|---|---|---|
| Protected branches | `PROTECTED_BRANCHES` | `FLIGHT_RULES_PROTECTED_BRANCHES` | agent guard, `session-start.sh`, git hooks, doctor | Branches the guard defends. POSIX ERE, matched case-insensitively, as `PR_ONLY_BRANCHES` and `NOTE_GATED_BRANCHES` are, by every hook — anchor it. To the agent guard and the `HOOK_SYNC=auto` sync, a pattern that does not compile protects every branch until it is fixed, and the guard's block names it — except on a mirror push, which any pattern refuses (#103: it used to protect none). The git hooks do the same: to `commit-msg`, every branch but a PR-only one is note-gated while it is broken (with `NOTE_GATED_BRANCHES` unset), and the refusal names it and prints the way past it. `off` disables four things at once: the guard's branch policy, the `checkout -b` rule, the ref gate, and — if `NOTE_GATED_BRANCHES` is unset — the note gate, whose default set is derived from this key. The secret scan stays on. |
| PR-only branches | `PR_ONLY_BRANCHES` | `FLIGHT_RULES_PR_ONLY_BRANCHES` | git hooks | No local merge or rebase; moves only through a PR. Default `^main$`. `off` is honoured by every hook that reads it — the ref gate, the local merge gate, the rebase gate and `commit-msg`'s squash guard stand down, and no merge counts as a back-merge — while `PROTECTED_BRANCHES` still applies. A pattern that does not compile makes every branch PR-only until it is fixed (#103: it used to make none): no local merge commit or rebase, and no pushed branch moves off its upstream. The refusal names the pattern and prints the way past it, for a branch the pattern does not mean: the command that finishes or repeats what it refused, with the pattern meant in `FLIGHT_RULES_PR_ONLY_BRANCHES`. Where a match grants an exemption — a back-merge needs no note, a PR-only branch is outside the derived note-gated set — it takes the pattern's exact case, so `^MAIN$` gates `main` without exempting it, and a refused back-merge says the case is why. |
| Note-gated branches | `NOTE_GATED_BRANCHES` | `FLIGHT_RULES_NOTE_GATED_BRANCHES` | `commit-msg` | Merging in needs a passing `pre-merge-check` note. **No default names**: unset, the gated set is *protected but not PR-only*, so a project gets the gate on whatever it calls its branches. Set it to override, or to `off`. A pattern that does not compile gates every branch until it is fixed, and the refusal names it and prints the way past it (#103). Because the default is derived, `PROTECTED_BRANCHES=off` empties it — name this key if the note gate should survive that. |
| Merge needs instruction | `MERGE_NEEDS_INSTRUCTION` | `FLIGHT_RULES_MERGE_AUTHORISED` (per-merge) | `commit-msg` | A merge into a protected branch is refused unless `FLIGHT_RULES_MERGE_AUTHORISED=1` is set on that merge. Default on. Set to `off` to drop the check. Either way the merge commit gets a `Merge-authorisation:` trailer. |
| Integration branch | `INTEGRATION_BRANCH` | — | `post-merge`, `session-start.sh`, skills | Where features merge. Default `main` everywhere. |
| Worktree path | `WORKTREE_DIR` | `FLIGHT_RULES_WORKTREE_DIR` | agent guard, `session-start.sh`, skills | Where worktrees live; suggested in the block message. Default `.ai/worktrees`. |
| Git-hook sync | `HOOK_SYNC` | — | `session-start.sh` | `auto`: the first session each day, and the first after a plugin update, runs `install.sh --from <plugin>/hooks/git --stale-only`, replacing hooks that are byte-identical to an older cached release and copying in missing ones (not a missing `install.sh`: nothing needs it to run the hooks, so doctor names it with the `cp` that restores it), then leaves the diff for you to commit. Only a **local** `core.hooksPath` inside the checkout the session runs in is touched — from a linked worktree, hooks in the main checkout are not synced (the write would land in that checkout's working tree); when one there is stale or missing the session says so and prints the command that updates this worktree's own copy instead (`--this-checkout`), to commit on its branch and merge, and when all are current it says nothing — never during a merge, rebase, `git am`, cherry-pick, revert or bisect — that skip is said, with the command to run once it is finished — nor on a protected branch, where the diff could not be committed — protected as the agent guard decides it, `FLIGHT_RULES_PROTECTED_BRANCHES` first and case-insensitively, and a `PROTECTED_BRANCHES` pattern that does not compile counts as protected, said as such: there it only compares, names what is behind or missing, lists apart what the command leaves alone, and prints the command to run in a worktree on a branch (silent when all are current); with `--this-checkout` it updates that worktree's copy even when git runs the hooks from the main checkout (without `--stale-only`, replacing what differs there too), and the merge brings it there — and the config is never rewritten. A headless session (`CLAUDE_CODE_SESSION_ATTENDED=0`) syncs until an attended session has run that day, spending no flag, and its notice reaches no screen — so an attended session says on screen when the hook directory has uncommitted changes, whoever made them, and when git cannot fully tell (it shows what git said). A hook you adapted on purpose carries a line `# flight-rules: adapted` and is left alone and accepted; one the sync cannot read is said to be unreadable and left alone, on screen even when nothing else was synced. Default `report`: `flight-rules-doctor.sh` names each stale or missing hook and prints the sync command, and nothing is written. It also warns, to the assistant only, about a project `install.sh` that is behind, differs while carrying flight-rules' marker, or cannot be read; a missing one is noted on the full report with the `cp` that restores it. |
| `/dg` comic | `DG_COMIC` | — | `/dg` (an instruction, not a hook) | `always` (default): every verdict ends with an ASCII comic of the best banter, with the banter score. `never`: no comic and no score. |
| `/dg` comic in PRs | `DG_COMIC_PR` | — | `/dg`, `pr-create` (instructions, not hooks) | Whether a review that is for a PR puts the comic, banter score included, in it. Strictly opt-in: `never` (default) keeps it out without asking, `ask` asks at the end of the verdict, `always` adds it. Ignored with `DG_COMIC=never`. |
| `/dg` round-2 wait | `DG_WAIT_MINUTES` | — | `/dg` (an instruction, not a hook) | Round 2 of the debate waits for the pre-review and the dependency scan; a run with no result after this many minutes counts as failed. A positive whole number; default `15`. |

Resolution order is **environment → `.ai/flight-rules.conf` → built-in default**, and
the conf file is read from the repo the command targets, so a session spanning several
repos gets each project's own policy.

> ⚠️ **The gate hooks read the conf from a state an incoming branch cannot edit — `reference-transaction` from the upstream, `pre-merge-commit`/`commit-msg`/`pre-rebase` from `HEAD`, not the working tree.** During a
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

## Wiring (Claude Code)

`hooks/wiring.test.sh` checks both paths by RUNNING every registered hook in each
environment — with `CLAUDE_PLUGIN_ROOT` set and with it unset — rather than by matching
filenames. It used to match, and passed 15/15 while the snippet below injected nothing.

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
  for. Only local branches and `origin/*` count, the name must match `PR_ONLY_BRANCHES` in
  its exact case, and the commit must be on `origin/<x>` when origin has it — a forced
  local `main`, a `MAIN` or `origin/Main`, or a stale `upstream/main` exempts nothing.
  The same hook refuses the commit that would complete a **squash merge** into a
  PR-only branch, which creates no merge commit and so never fires `pre-merge-commit`.
  **A passing note is not consent.** The agent writes that note itself, so a stamped
  merge nobody asked for used to land with a green `✅ Pre-merge check verified` —
  measured 2026-09-10, no warning of any kind. The merge is now refused unless it says
  who wanted it: `FLIGHT_RULES_MERGE_AUTHORISED=1 git merge …`. A refused merge is left
  in progress, so the box gives `FLIGHT_RULES_MERGE_AUTHORISED=1 git commit --no-edit`
  to finish it — a second `git merge` fails there. An agent *can* set that
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
- **`pre-commit`** — the secret scan, on what the commit will actually record: a
  provider key (AWS, `sk-…`, GitHub, Slack, Google), a PEM private-key header, or a
  `.env` added, edited or renamed away (templates exempt; removing one is the only `.env`
  change let through). Every binary is read whole. Git runs it after building the commit's index, so
  `git add f && git commit`, `commit -a`, `commit <path>` and a `GIT_INDEX_FILE=`
  prefix are all covered — the agent guard scans before the command runs and saw none
  of them (#71, #72) — and a human's commit is scanned too. It is narrower than the
  agent guard on purpose: the guard's `password = "…"` heuristic warns an agent but
  would block too many ordinary commits here. A merge being concluded has its
  conflict resolution scanned, not the commits coming in: the staged diff against
  git's `AUTO_MERGE` (git ≥ 2.42; the file, or in a reftable repository the pseudo-ref —
  never a branch or tag of that name) is what was typed while resolving. Without
  `AUTO_MERGE` everything staged is scanned, incoming commits included (#101: skipping
  the whole commit let a key typed into a resolution through). The accepted cost: an
  incoming commit is scanned only if this hook ran when it was made, so one from before
  it, or made with `--no-verify`, lands with the merge. "Being concluded" means git's
  `MERGE_HEAD` file exists and names a commit `HEAD` does not already contain (a branch
  or tag named `MERGE_HEAD` does not count, nor a leftover file naming `HEAD` or an
  ancestor, from which git makes an ordinary commit), and the
  hook says on every such commit what it scanned, naming the commit coming in, so a
  `MERGE_HEAD` left behind shows instead of narrowing the scan unseen; a `merge --squash` is an
  ordinary commit and is scanned. A clean `cherry-pick`/`revert` does not run
  `pre-commit`; one that stopped on a conflict and is finished with `--continue` does.
  Override for a checked false positive: `--no-verify`, the owner's call — the refusal
  does not print it, because an agent reads it too. **Already have a `pre-commit`** (a linter,
  lint-staged)? Rename yours `pre-commit.local` beside this one: it runs after a clean
  scan and its exit status decides the commit. **Upgrading from 0.22.x:** a plugin
  update cannot copy git hooks, so this one arrives only when you sync them in —
  `install.sh --from`, below; `flight-rules-doctor.sh` — run at session start — reports
  it missing and prints that command. Tests: `secret-scan.test.sh`.
  **Install all of `hooks/git/`**, or the gate is half built; `install.sh` refuses
  unless all six bare-named hooks are present.
- **`post-merge`** — after a merge into the integration branch, writes a cleanup note
  (stale worktrees, deletable branches) that the next AI session picks up. Under each
  stale worktree it names the processes still running from it — working there, or with
  its path in their command line — so a server or database a check started is stopped
  before the worktree goes; it lists them and stops nothing (#109).
  Optionally (`CLEAR_AI_CONTEXT=1`, off by default) also clears Claude Code's stored
  conversations for the project so the next session starts fresh — read the guarded
  block in the script before enabling.
- **`install.sh`** — one-time per clone: `chmod` the hooks, set
  `core.hooksPath`, and set `merge.ff false` so the merge gate always fires
  (a fast-forward merge would silently skip `pre-merge-commit`). It installs into
  the directory the **local** `core.hooksPath` names, else `.ai/hooks/`, and writes
  the path once, relative to the repo root, so every worktree resolves its own copy;
  a path already set is never rewritten (an absolute one written from a worktree
  outlived the worktree and left every checkout running no hooks).
  **After a plugin update**, `bash <plugin>/hooks/git/install.sh --from <plugin>/hooks/git`
  copies the six hooks and itself into the project first, then installs as usual —
  the update refreshes the agent hooks but cannot touch these, which are the
  project's committed files (AppliHawk ran four 0.22.0 hooks under a 0.23.0 plugin,
  2026-10-12). From a linked worktree whose hooks are in the main checkout, that form
  is refused — it would write into the main checkout's working tree — and prints the
  one to use there, `--this-checkout`, which updates the worktree's own copy for its
  branch to commit and merge. If that directory does not exist, git runs no hooks in
  any checkout; the refusal says so and prints the install to run in the main checkout. `--stale-only` replaces only a copy byte-identical to some release in
  the plugin cache, so a project's own adaptation is left alone and named — mark it
  with a line `# flight-rules: adapted` and doctor accepts it too. Two exceptions are
  left alone without a word: an `install.sh` that is the project's own script, not
  flight-rules' (it lacks the installer's header phrase), and a missing `install.sh`,
  which doctor names instead; without the flag
  every differing hook is replaced, except a `pre-commit` that is not flight-rules'
  at all, which is refused with the rename that keeps it running. A copy that fails
  is an exit, never a "synced" line. `flight-rules-doctor.sh` prints the command
  whenever a hook is missing or behind, or the project's `install.sh` is behind,
  differs while still carrying flight-rules' marker, or cannot be read (a warning,
  not on screen: it guards nothing; one without the marker is the project's own and
  is not named; a missing one is noted with the `cp` that restores it — this
  checkout's copy, from a worktree too), and
  `HOOK_SYNC=auto` in the conf has
  `session-start.sh` run the `--stale-only` form itself. Either way the result is a
  diff to review and commit. Tests: `install.test.sh`.

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
  `echo main` refused the deletion of a feature branch). Both fixed 2026-09-10. On a **protected** branch of the project
  it denies `git checkout -b`/`-B` and `git switch -c`/`--create` — branches are
  created as worktrees (workflow rule 6), and the block shows the command. That applies
  while you stand on a **protected** branch, which is when a branch made in place puts
  feature work in the main checkout. It was nominally every branch until 2026-09-14,
  though never actually enforced as such: a `git commit` in the same command elected
  `commit` and branch creation was never judged at all. "The
  project" is its main checkout *and every worktree of it* — they share one
  `--git-common-dir`, which is how a worktree is told from an unrelated repo whose
  branches are none of this project's business.
  The target repo is resolved **per segment**: a `cd` sets it for the segments after
  it, a `git -C <dir>` sets it for its own segment only, and `-c`/other global options
  are normalised away so every matcher sees `git <verb>`. Until #61 it was resolved
  once per command — the last `cd` anywhere, else the first `-C` anywhere — so
  `git -C /other status && git commit -m x` on a protected branch was allowed and the
  secret scan read `/other`. A `cd` inside `( … )` or `$( … )` ends at the `)`, as in
  the shell (#70) — for branch policy, a best guess: a paren inside quotes, a heredoc
  or a `case` pattern is not told from a real one, so the scope can be wrong either
  way, and the ref gate is the backstop. The secret scan does not depend on it: it
  reads the repo of **every** commit (#69), the cwd, and every repo any `cd` in the
  command names, so a key staged in a repo the command visits blocks the commit and
  the deny names the repo. A merge in progress is exempt so conflicts can be
  resolved.
  Regardless of branch, a commit is denied with a `.env` added, edited or renamed away (templates
  `.env.example|sample|template|dist` and `.env.md` exempt; removing one is let
  through), a provider key (AWS,
  `sk-…`, GitHub, Slack, Google), any PEM private-key header, or a credential literal
  outside test and prose files (`docs/`, `locales/`, `i18n/`, `translations/`,
  `*.md|rst|txt` — keys are still caught
  there). A line marked `flight-rules: allow` is a reviewed exception. It reads the
  index as it stands before the command runs, so anything the same command stages is
  not in it; the git `pre-commit` hook is the scan that sees those. The repo's own diff
  settings — colour, an external diff, a textconv, a `-diff` attribute, `diff.relative`
  — do not change what it reads, and short of the size limit below nothing a file
  contains exempts it: a NUL or `\001` used to mark a file "binary" and skip the
  credential-literal check for it, so one planted byte muted the warning (#76). The
  cost is that a small binary holding a quoted credential-shaped string is reported
  too; `flight-rules: allow` has no line to sit on in a PNG, so a checked false
  positive there is committed by the owner, whose own commands this guard does not
  gate, or lives under a fixtures/ path. A real binary (a NUL in its first 8000 bytes) over
  1 MB is not read, because reading a large asset whole can outlast the hook's timeout
  and let the commit through unscanned; the git `pre-commit` hook reads those.
  Needs `jq` or `python3`; with neither it denies git commands with an install hint
  rather than silently switching off. It also uses `sed`, which is in every base system
  the hooks target. The compound-command SPLIT is pure bash, though: when that shelled
  out to `tr`, a PATH without `tr` made a forced push and a branch deletion naming a
  protected branch ALLOWED from a feature branch, silently — the ref they name is read
  by splitting the command, and nothing announced the dependency.
  Tests: `pre-commit-check.test.sh` (no arguments, no network).
- **`flight-rules-doctor.sh`** — is the enforcement actually installed, and current? Checks `core.hooksPath`,
  every hook's executable bit *and* that each one still contains the string that makes
  it that hook (a present, executable stub enforces nothing; one it cannot read is said
  to be unreadable, ❌, since git cannot run it either), that each one is this
  release's copy — byte-identical to an older cached release is ❌, differing from every
  release is ⚠️ since it may be the project's own adaptation, and either prints the
  `install.sh --from` command — `merge.ff`, the guard's parser, the conf's keys and
  regexes, that every script `.claude/settings.json` wires exists, and that the guard
  is wired once and actually enabled, and — with the plugin on — that no command or
  skill of the user's or project's own, named like a plugin skill, runs in its place
  (⚠️; a file with a line starting ``Read and follow `…skills/<name>/SKILL.md` `` or
  ``Use the `flight-rules:<name>` skill`` is a pointer, not a shadow) — every one a state that has
  failed silently before. `session-start.sh` runs it daily and prints only problems.
  Tests: `flight-rules-doctor.test.sh`.
- **`session-start.sh`** — SessionStart banner: once a day per project (a headless session spends no
  flag, so it runs until an attended one has that day), and again after a plugin update, runs `flight-rules-doctor.sh` and lists worktrees whose branches are already merged
  so they get cleaned up. Doctor's ❌ problems, the command that fixes them, and a hook sync
  are printed as `systemMessage`, so they appear on the user's screen — in a project
  that uses flight-rules (`.ai/flight-rules.conf` at the root, or flight-rules' hooks
  installed). A repo with no `core.hooksPath` is shown the install hint
  once; one running another tool's hooks (husky), or a directory outside a repo, nothing.
  ⚠️ warnings never go on screen, since some are true by choice and would repeat daily.
  Everything goes to the assistant as `additionalContext` (with neither `jq` nor `python3`, plain stdout, which only the
  assistant sees). Reads
  `INTEGRATION_BRANCH` and `WORKTREE_DIR` from `.ai/flight-rules.conf` when present.
  A branch is matched by its whole name: `grep -w` counted `-` as a word boundary and
  reported a worktree on `fix/auth` as merged because `fix/auth-tokens` was.
  Tests: `session-start.test.sh`.
- **`session-start-rules.sh`** — injects `rules/engineering-principles.md` into the
  session. A plugin surfaces skills, commands and hooks as live primitives, but its
  `rules/*.md` are just files: installing the plugin does not put them in the model's
  context, and this is what does.

  **The injection happens once, at session start, and updating the plugin does not redo
  it.** `/reload-plugins` refreshes skills and hooks on disk while the running session
  keeps the text it was given — reported 2026-09-15 by a session that had just read the
  new version's SKILL.md from disk and was still following the previous version's
  principles. Nothing in this repo can re-inject into a live session; **a new session is
  what picks up a rules change.** So the header names the plugin version, which turns
  invisible staleness into something a reader can check against the plugin directory.
  Tests: `wiring.test.sh` — the rules arriving is asserted before the version in every
  install shape, because reading the version must never cost the rules.

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

A third, confirmed by test: **`git merge --squash` lands on a note-gated branch without
a `pre-merge-check` note.** The note gate reads `MERGE_HEAD`, and a squash writes
`SQUASH_MSG` instead, so the commit-msg hook sees an ordinary commit and lets it
through. `--squash` is a deliberate choice of merge strategy, typed by someone who knows
what it does — it is not the habit-and-wrong-tab failure this layer exists to catch, and
gating it would mean treating every commit on the branch as a possible merge. On a
PR-only branch this does not arise: `reference-transaction` refuses the ref move whatever
produced it.

**The design rule follows: close the paths reachable by accident; do not contort the
design to stop someone acting deliberately.** A guard that catches the careless case
and is honest about the willful one is more useful than one that poses as a security
boundary and isn't.

**It assumes a competent developer.** flight-rules exists so the small, easily
overlooked thing is not missed — not to babysit. Where it cannot proceed safely it
stops, says why, and prints the command where there is one. Its own automation (the
sync, doctor) does not act on the developer's behalf to get round the stop — it makes
no branch or worktree for them (#99) — and it adds no block for a mistake a competent
developer would not make (owner, 2026-10-21).

### With the plugin alone, a protected branch is only half guarded

`core.hooksPath` cannot be set by a plugin — git offers no mechanism — so the **git**
hooks need one `install.sh` run per clone. Until that happens a project has the agent
guard and nothing else, and the agent guard does not match every way a ref moves.
Measured 2026-09-11 on a plugin-installed project that had not run `install.sh`, on a
protected PR-only `main`:

| Command | Verdict |
|---|---|
| `git commit`, `git rm` | blocked (agent guard) |
| `git merge`, `git cherry-pick`, `git revert` | **allowed** |
| `git branch -f main …`, `git update-ref refs/heads/main …` | **allowed** |

`git merge feature/x` was confirmed moving `main` with no layer objecting. `flight-rules-doctor.sh`
reports this at session start — naming `core.hooksPath` and `merge.ff` with the commands
to fix both — so the state is loud, not silent. **Run `install.sh`.** With the git hooks
present, `reference-transaction` refuses every one of those.

**Teaching the agent guard to cover them was tried and abandoned**, and the attempt is
recorded so it is not tried a fourth time. Adding matchers for those five commands
produced, in one afternoon: a no-op `git rebase --abort` prefix that disarmed the whole
new matcher (`main` moved, merge landed); `git branch -M <name>` renaming the protected
branch out of existence; `git update-ref --stdin`, whose refs are not in the command
string at all; quoted target names; and `git merge X && git branch -f main Y` escaping
because the dispatch is a first-match chain, so targets are read only from the first
matcher that fires. The suite reported 553 passed, 0 failed throughout.

The lesson is a layering one, and it is the same error twice in opposite directions. The
guard was once *relaxed* on the belief that the ref gate backstopped it — it does not
cover the destructive class, which moves no ref. It was then *tightened* on the belief
that it could do the ref gate's job — it cannot, because matching command strings is
open-ended and each new matcher brings its own bypass. **The agent guard is an early,
specific message. The git hooks are the enforcement.** A gap in the guard is closed by
installing the git hooks, not by adding a matcher.

There is also a cost to trying: a guard that blocks legitimate work teaches the next
agent to route around blocks, and the block message names the opt-out. A ruleset
restrictive enough to be safe against every shape is one nobody follows.

### The agent guard over-blocks prose. That is the accepted trade.

It matches a git verb anywhere in a command SEGMENT, so writing *about* a git command
can read as running one — `echo "never git rm on main" >> notes.md` is refused. In a
repo whose product is documentation about git, that is not rare.

A segment, not the whole string: until 2026-09-13 the classifiers looked at everything
between the first character and the last, so a flag from one command was read as
another's. `git push origin dev && … | tr -d ' '` was refused as a remote branch
deletion because of `tr -d`, `git clean -n && rm -f x` as `git clean -f`. The target
parsers had run per segment since 2026-09-10; the classifiers that pick which parser to
use had not.

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
or tool that bypassed the agent layer) at merge time. The secret scan is layered the
same way: the agent guard denies early with the reason, and git's `pre-commit` scans
what the commit really records. Keep both.
