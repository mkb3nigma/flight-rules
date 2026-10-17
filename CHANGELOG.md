# Changelog

What changes for someone who installs a new version — behaviour first, because that is
what arrives without being asked for. Each entry says what the old version did and what
this one does; every verdict below was run against both, not reasoned about.

## 0.24.1 — 2026-10-16

### Upgrading

Nothing to run: the change is in `skills/dg/SKILL.md`, which the plugin update brings.
If your project wires a cross-family pre-reviewer in `.ai/skills/dg/EXTENSIONS.md`,
check that command against the six points below — the extension replaces the step, so
the skill's text never reaches it. AppliHawk's did not pass on first check: it pinned
`--model gemini-3.8-flash-high`, and its `agy` runs came back exit 0 and empty.

### `/dg`: a contract for any reviewer CLI, not a Codex recipe

0.24.0 named no vendor for the independent pre-review, but its completion check was
written in Codex terms and its only worked example was a Codex command (beside a bare
`claude -p "…"`), so wiring another CLI meant guessing. 0.24.1
states what any wired command must do:

- **name no model** — the choice stays in the CLI's own config, or its default. A pinned
  `gpt-5.5` failed Codex pre-reviews with "does not exist" and "not supported"
  (2026-09-09, 2026-10-16);
- **set effort to `high`** where the CLI has the setting, else say so in the header;
- **run read-only, or with no tools** where the CLI has no read-only mode — and no tools
  means none from MCP servers or plugins either: `claude -p --tools ""` still
  loaded every connected MCP server's tools until `--strict-mcp-config`;
- **feed the input the way the CLI reads it** — `agy -p` 1.4.0 ignores piped stdin;
- **keep the final message apart from stderr**, and count a run only on the marker line
  and exit 0 together — never on exit 0 or a status field alone: `agy` returned `"status":"SUCCESS"`, exit 0 and an
  empty reply on a denied tool call;
- **report the model that ran.** A same-family or unreported model counts, under a new
  header form, `✅ <reviewer> (<model>, not cross-family)` — `agy` also serves Claude
  models, so a CLI is not a family.

Both examples now meet it, and each was run as written: Codex with
`-c model_reasoning_effort=high`, and `claude -p --effort high --tools ""
--strict-mcp-config --output-format json`, which replaces the bare `claude -p "…"`.

## 0.24.0 — 2026-10-12

### Upgrading — once more by hand, then never again

**Sync the git hooks after this update.** A plugin update refreshes the agent hooks
but cannot touch your project's git hooks, which are committed files, and Claude Code
has no install or update event a plugin could act on. AppliHawk updated to 0.23.0 and
kept running four 0.22.0 hooks with nothing to say so. From this release the sync is
one command, and doctor prints it with the real paths whenever a hook is missing or
behind:

```bash
bash <plugin>/hooks/git/install.sh --from <plugin>/hooks/git --stale-only
```

Run the **plugin's** `install.sh`, as above, not the copy in your `.ai/hooks/`: the
0.23.0 copy there ignores `--from`, prints "✅ git hooks installed" and rewrites
`core.hooksPath` absolute, which is the bug below. After this sync your copy is the
0.24.0 one. `--stale-only` replaces only a hook byte-identical to an older release in the
plugin cache, and copies in a missing one. A hook you adapted is left alone and named. Review
the diff it leaves and commit it.

**To make it automatic, opt in:** add `HOOK_SYNC=auto` to `.ai/flight-rules.conf`. The
first session each day, and the first after an update, then runs that command itself
and tells you what to commit. It touches only a local `core.hooksPath` inside the repo,
never mid-merge or mid-rebase, and never rewrites the path. The default is `report`,
which writes nothing.

**Start a new session after updating.** `/reload-plugins` swaps the agent guard, but
the session-start hooks — the principles, doctor, the sync — run only when a session
starts.

**`hooks/doctor.sh` is now `hooks/flight-rules-doctor.sh`**, so it is not confused with
Claude Code's own `/doctor`. Anything that calls it by path needs the new name.

### Behaviour changes

**What needs you is shown to you.** The session-start check printed its findings as
plain text, which Claude Code gives to the assistant and never puts on the screen; a
fresh install or an update with a stale hook said nothing to the person who had to act.
Doctor's ❌ problems, with the command that fixes them, and a hook sync now arrive as a
message you see when the session starts, in a project that uses flight-rules
(`.ai/flight-rules.conf` at the root, or flight-rules' hooks installed). A
repo with no git hooks set up is shown the install hint once; one running another
tool's hooks (husky), or a directory outside a repo, is shown nothing. ⚠️ warnings stay with the assistant only — some are true
by choice, and on screen they would repeat every day. The assistant still gets
everything. The sync command doctor prints is the `--stale-only` form, so running it as
printed never replaces a hook you changed, and a clone of a project that committed its
hooks is given the plugin's `install.sh` to wire them, never the repo's own copy. In a repo with no git hooks installed:

| | 0.23.0 | 0.24.0 |
|---|---|---|
| on your screen at session start | nothing | **the doctor message** |
| doctor's `core.hooksPath` line | `(hooks/git/install.sh, …)` — a path inside the plugin | **the full command**, with the plugin's real path, that installs into `.ai/hooks/` |

**A project's own `json.py` no longer runs at session start.** On a machine without
`jq`, the session-start hooks build their JSON with `python3`, which imported modules
from the project directory first, so a `json.py` in a cloned repo ran as code when a
session opened. They now run Python isolated (`-I`). Reproduced on 0.23.0's
`session-start-rules.sh` and fixed in both hooks.

**Doctor reports a git hook that is behind, not only one that is missing.** Standing in
a project whose `commit-msg` is the 0.22.0 copy, every other hook current:

| | 0.23.0 | 0.24.0 |
|---|---|---|
| doctor's `commit-msg` line | ✅ installed and executable | **❌** is the flight-rules 0.22.0 copy |
| `install.sh --from <plugin>/hooks/git --stale-only` | ignored, nothing synced | **commit-msg replaced**, diff left to commit |
| `HOOK_SYNC=auto` in the conf | ⚠️ unknown key | accepted |

A hook that matches no release is ⚠️, since it may be your own adaptation. Add a
comment line `# flight-rules: adapted` to it and doctor accepts it, and the sync leaves
it alone; `/rules-sync` still shows its diff against each new release.

**`install.sh` no longer rewrites `core.hooksPath`.** Re-run from a worktree, it wrote the
worktree's absolute path into the shared repo config, so removing the worktree left
every checkout running no hooks. A path already set is kept; a fresh install writes it
relative to the repo root.

| Re-run `install.sh` in a worktree, `core.hooksPath=.ai/hooks` | 0.23.0 | 0.24.0 |
|---|---|---|
| `core.hooksPath` afterwards | `<worktree>/.ai/hooks`, absolute | `.ai/hooks`, unchanged |

**`core.hooksPath = ~/…` is expanded.** Doctor, session-start and `install.sh` read the
setting raw and joined `~/x` to the repo root, where git does not look: doctor called a
working gate "does not exist — git runs NO hooks", session-start did not recognise the
project as using flight-rules, and `install.sh` made a literal `~` directory in the
repo and wrote the hooks there. They now read it as git does. A `~` path outside the
repo is still not synced: `--stale-only`, and so `HOOK_SYNC=auto`, refuses it as
outside this repository, as it does any absolute one.

**A control byte no longer exempts a file from the credential check (#76).** The agent
guard skipped its `password = "…"` heuristic for any file whose diff held a NUL, so one
planted byte muted the warning for everything else in that file. The six key patterns
were never affected. Staging, on a feature branch:

| Staged file | 0.23.0 | 0.24.0 |
|---|---|---|
| `app.py`: a NUL on one line, `password = "…"` on another | allowed | **denied** |
| the same with a `\001` byte | allowed | **denied** |
| a small binary holding `password = "…"` | allowed | **denied** |

The last row is the cost: a small binary with a quoted credential-shaped string is now
reported. `flight-rules: allow` has no line to sit on in a binary, so a checked false
positive there is committed by you, or kept under a `fixtures/` path. A binary over
1 MB is still not read by the agent guard; the git hook reads it for keys.

**An added line starting `++ ` is scanned for keys (#77).** In the diff it reads
`+++ …`, the shape of a file header, and the agent guard dropped it before the six key
patterns ran: `++ AKIA…` was committed with the agent guard's leave. The git
`pre-commit` hook already read it, and still refuses it.

**A release PR needs `/dg` on its whole diff.** `pr-create` step 2b: `/dg
origin/main...<sha>` on the commit step 2a tested, with each finding's disposition in
the PR body; a critical finding is yours to decide. The `release review` check fails a
PR into `main` whose **Adversarial review** section is missing or empty, and re-checks
when the body is edited. `/dg` takes a `<base>...<head>` range for it.
Warrant: a data-loss bug in AppliHawk 0.16.0 that every per-branch gate had passed,
found by `/dg` on the release diff (aa4ca42e, 2026-10-12).

**`/dg` no longer counts a dead pre-review as a clean one.** The pre-reviewer is asked
to end with `PRE-REVIEW COMPLETE: <n> findings`; a run whose final message does not
end with that line, or a CLI run that exits non-zero, is reported as
`⚠️ unavailable — <why>` once a same-family reviewer has failed the same check too.
A failed Codex turn in this release's own review printed text that read as a clean
verdict. Codex or any second model being unavailable is a warning in the header, never
a reason to stop the review.

## 0.23.0 — 2026-10-12

### Upgrading — one step a plugin update cannot do

**Copy in the new git hook and re-run `install.sh`.** 0.23.0 adds `hooks/git/pre-commit`,
the secret scan that sees what a commit really records. A plugin update refreshes the
agent hooks but cannot copy git hooks into your project, so until you do this it is not
running:

**Already have a `pre-commit`** (a linter, lint-staged)? Rename it first, or the `cp`
below replaces it: `mv .ai/hooks/pre-commit .ai/hooks/pre-commit.local`. It then runs
after a clean scan, and its exit status decides the commit.

```bash
cp -n <plugin>/hooks/git/pre-commit .ai/hooks/ && chmod +x .ai/hooks/pre-commit
.ai/hooks/install.sh
```

`cp -n` copies nothing, silently, if a `pre-commit` is still there — skip the rename
and you keep only your own hook, which `doctor` then reports.
`doctor` (run at session start) reports the hook missing and prints the `cp` line with
the real path, and says where a project's own `pre-commit` goes. `install.sh` now refuses
to finish without it.

### Behaviour changes

**A key staged by the same command is caught.** The agent guard scans the index *before*
a command runs, so anything the command itself stages was never seen. The new git
`pre-commit` hook scans the index git actually commits — and a human's commit too.
Standing on a feature branch, an AWS key involved:

| Command | 0.22.0 | 0.23.0 |
|---|---|---|
| `git add leak.txt && git commit -m x` | committed | **refused** (git hook) |
| `git commit -am x`, key in a tracked file | committed | **refused** (git hook) |

The same holds for `commit <path>`, `--include` and a `GIT_INDEX_FILE=` prefix (#71,
#72). It is narrower than the agent guard on purpose: provider keys, PEM private keys and
`.env` files only, not the `password = "…"` heuristic, which would block too many
ordinary human commits. A merge being concluded is not re-scanned; a clean `cherry-pick`
or `revert` does not run `pre-commit` (one finished with `--continue` after a conflict
does). If git cannot read what is staged, the commit is refused with git's reason, not
passed unscanned — including, by design, a blobless partial clone that cannot reach its
remote to fetch a file's old contents.
`--no-verify` is the owner's override; the refusal does not print it, because an
agent reads the refusal too.

**The agent guard's secret scan reads the repo each commit actually goes to.** A key staged
in the repo being committed to; `O` a clean sibling repo:

| Command | 0.22.0 | 0.23.0 |
|---|---|---|
| `git -C O commit -m a && git commit -m x` | allowed | **denied** (#69) |
| `(cd O && make) && git commit -m x` | allowed | **denied** (#70) |
| with `color.ui=always` set, `git commit -m x` | allowed | **denied** |
| with a `-diff` attribute on the file, `git commit -m x` | allowed | **denied** |

The repo's own diff settings — colour, an external diff tool, a textconv, a `-diff`
attribute, `diff.relative` — no longer change what is scanned. Every staged file is read
as text, except a real binary over 1 MB, which the agent guard skips because reading it
whole can outlast the hook's timeout (a killed hook lets the command through). Which
files are binary is decided by their content, not `.gitattributes`: an attribute no
longer hides source files from the credential check or has a large binary read whole.
The git
hook reads those whole, wherever the key sits in them. If git cannot read what is
staged, the command is denied with git's reason, not allowed unscanned. A `cd` or `-C`
target written with `~` or `$HOME` is followed. One written with any other `$VAR`, typed
from outside every repo, is still not scanned by the guard; the repo's own git hook scans
it. The
credential check reads the diff once, so a commit of thousands of files is checked
whole — it was skipped past the argument limit.

**Branch policy is judged per segment of a command.** On a protected branch:

| Command | 0.22.0 | 0.23.0 |
|---|---|---|
| `git -C O status && git commit -m x` | allowed | **denied** (#61) |

A `cd` applies to the segments after it, a `git -C` to its own segment only, and a `cd`
inside `( … )` or `$( … )` ends at the `)`.

**Removing a `.env` is the one `.env` change allowed.** Both the agent guard and the git
hook refuse a `.env` that is added, edited, renamed away or retyped; templates
(`.env.example|sample|template|dist`, `.env.md`) are exempt.

| Command | 0.22.0 | 0.23.0 |
|---|---|---|
| `git rm .env && git commit -m x` (a tracked `.env`) | denied | **allowed** |
| editing a tracked `.env`, then `git commit -m x` | denied | denied |

A project that commits a `.env` on purpose does so with `--no-verify`, deliberately.

**A commit command visiting more than 24 directories is denied.** The scan now reads
every repo a command `cd`s into, and its cost grows with each. Past 24 the guard denies
and asks for the commit to be run on its own, rather than risk the timeout. None of 949
real commit commands came near it (the most was 6).

### Fixed

- **The guard was slow on long commands** — a heredoc splits into a segment per line, and
  it forked once or twice per segment. A 64 KB heredoc and a commit took 6s on 0.22.0
  and take 1s now; a large enough one could reach the hook timeout and run unchecked
  (#73).
- `commit-msg` glued the `Merge-authorisation:` line to the subject, so git never saw a
  trailer and `git log --oneline` showed it on every owner merge (#62).
- `post-merge` recorded `unknown` for "Merge remote-tracking branch 'origin/x'" subjects,
  and lost its "← just merged" line (#63). Its note now also says when `git branch -d`
  will refuse a branch because its upstream does not have it yet — "(refused until
  origin/dev has it — push that first)" — instead of offering it as safe to delete, and
  offers no `git branch -d` for a branch merged from `origin/` that has no local copy.
- `doctor` reported correctly wired hooks as missing when wired from `.claude/hooks/` or
  through a `$VAR` prefix — `$CLAUDE_PROJECT_DIR`, quoted or not, included (#66) — and
  "no agent guard wired" when the plugin was enabled at project scope (#67). A hook wired
  under `$HOME` or `~` is checked in the home directory, not the repo; a quoted path
  with a space is checked whole; and a `$VAR` or `~` the shell never expands (inside
  single quotes) is reported, since that hook never runs. It now also reports a `pre-commit.local` that is not
  executable, which the scan would skip silently.
- The session-start check ran once a day, so after an update that day `doctor` — which
  reports the missing git hook above — waited until the next. It now also runs on the
  first session after the plugin version changes.
- `install.sh` listed a directory under `.ai/hooks/` as an active hook; hook comments named
  paths that exist only in this repo.

### Changed

- `rules/engineering-principles.md` §4: a comment is stale when its reason has gone, not
  when it is old; unfinished work is an issue, not a TODO. `/pre-merge-check` item 15
  now fails an added TODO that cites no issue (#68).
- `rules/engineering-principles.md` had its release review, read as the assistant that
  receives it. Rewritten where the literal reading invited the failure: "skip error
  handling for scenarios that cannot occur" (a check's own failure must now fail
  loudly), "store and compute in UTC" (calendar arithmetic belongs in the owning zone),
  "every code change ships with tests" (refactors and new code had no workable reading).
  New: an action nothing can undo needs a person's yes; a universal claim names what was
  checked; a decision asked for carries its own reasoning, not a pointer to it; when two principles conflict, the blocked-command and irreversible-action
  stops win. Nothing cut. An advisory rule is no longer cut for being advisory or for
  not having fired lately — only when its reason is gone.
- The principles' two hard stops — a blocked command, an action nothing can undo — have
  their own section, first, headed "Not yours to override". They were bullets
  5–6 of §4, under a heading that says keep going. Wording unchanged; §1–§7 keep their
  numbers.
- The injected rules header names the plugin version, so a session still holding an
  older version's rules after an update can tell.
- `hooks/README.md` reads in order: install, configure, wire, then the per-hook reference
  (#64).
- `/dg`'s Codex pre-review example pipes the brief on stdin.
- `secret-scan.test.sh` — the git hook's suite. Ninth suite.

## 0.22.0 — 2026-09-14

### Behaviour changes

**A command is allowed only if every part of it is allowed.** The guard used to pick one
action for a whole command and judge only that, so a harmless-looking part could suppress
judgement of the rest. Standing on a feature branch:

| Command | 0.21.5 | 0.22.0 |
|---|---|---|
| `git commit -m x && git push --force origin main` | allowed | **denied** |
| `git commit -m x && git branch -D main` | allowed | **denied** |

Each half alone was already denied in 0.21.5. This is a coherence fix, not a security
one — naming a protected branch on a forced push is deliberate, and these hooks are
guardrails against mistakes, not a security boundary.

**Creating a branch in place is no longer refused on every branch.** It is refused while
you stand on a protected branch, which is where a branch made in place strands feature
work in the checkout you meant to keep clean.

| Command | 0.21.5 | 0.22.0 |
|---|---|---|
| `git checkout -b scratch` on a feature branch | denied | **allowed** |
| `git checkout -b scratch` on a protected branch | denied | denied |

The rule was nominally universal and was never actually enforced when a `git commit`
shared the command; made consistent, universal cost 7 of 405 real commands in the
author's own transcripts. Narrowed deliberately rather than left inconsistent.

**A flag belonging to one command no longer convicts another.** The matchers looked at
the whole command string, so an unrelated `-d`, `-f` or `--hard` elsewhere in a pipeline
changed the verdict.

| Command on a protected branch | 0.21.5 | 0.22.0 |
|---|---|---|
| `git clean -n && rm -f /tmp/x` | denied as `git clean -f` | **allowed** |
| `git push origin dev && … \| tr -d ' '` | denied as a branch deletion | **allowed** |

**A merge in progress waives less than it did.** The waiver covers the merge commit and
the working-tree commands that resolve a conflict. It used to be written as an exclusion,
which quietly waived a local delete of a protected branch — something no part of
committing a merge requires.

### Fixed

- **The guard failed open without `tr` on `PATH`.** The compound-command split shelled out
  to it, so the parsers that resolve which ref a push or a branch deletion names saw
  nothing, and a forced push at a protected branch from a feature branch was allowed —
  silently. The split is pure bash now.
- **`PROTECTED_BRANCHES=off` turns off more than it said.** It also stops branch creation
  being refused and — when `NOTE_GATED_BRANCHES` is unset — empties the note gate, because
  the note-gated set is derived as *protected but not PR-only*. **If you set `off` and rely
  on the note gate, name `NOTE_GATED_BRANCHES` explicitly.** `doctor` now warns. What `off`
  does *not* disable: the secret scan, and the PR-only local merge and rebase gates.
- `doctor` reported a healthy install for three states that enforced nothing: hooks
  replaced by empty stubs, a `.claude/settings.json` path that does not resolve, and a
  plugin listed but switched off.
- `/pre-merge-check`'s secrets scan had no patterns to run in a plugin install — none of
  the three paths it read them from exists there. It now carries the patterns.
- `post-merge`'s cleanup note emitted `git branch -d + <name>` for a branch held by
  another worktree, and dropped a branch whose name contained another's as a prefix.
- The stale-worktree reminder matched branch names loosely: `fix/auth-tokens` being merged
  reported a worktree on the unmerged `fix/auth`.

### Added

- **`/pr-create` step 2a** — a release PR runs the full test suite on the exact commit
  being pushed and reports its sha. Per-branch checks prove each change in isolation; the
  release ships the sum. Proposed by the AppliHawk project after a release PR went red on
  its first CI run with every merged branch individually green.
- A threat-model statement at the top of both READMEs: these are guardrails against
  workflow slips, not a security boundary, and an assistant given full control of a
  machine is beyond anything a repository of rules can reach.
- `docs-consistency.test.sh` — checks that this repo's documents agree with each other,
  with `.ai/flight-rules.conf` and with CI. Eighth suite.

### Changed

- `rules/engineering-principles.md`, injected into every session, had its release review:
  four bullets cut as duplicates or generic advice, two merged, one moved to the section
  it belonged in. No rule was dropped.
- `hooks/README.md` gained a contents block; at 430 lines it had no navigation.
