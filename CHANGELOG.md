# Changelog

What changes for someone who installs a new version — behaviour first, because that is
what arrives without being asked for. Each entry says what the old version did and what
this one does; every verdict below was run against both, not reasoned about.

## 0.29.0 — 2026-11-11

Every stop now prints the one command that goes ahead anyway —
`FLIGHT_RULES_GO_AHEAD=1` in front of the command that finishes what was stopped — so
flight-rules never blocks the developer; it is the person's to run, and the agent guard
refuses an assistant's command that sets it. New branches start from the local
integration branch, with origin's work pulled into it first, so a merge made here and
not yet pushed is in them; the routes the hooks print when they refuse now say the
same, and work in every layout they were tried in. A `pre-merge-check` note now has to
show the check ran. A direct change to a protected branch that is not PR-only is warned
of, never refused, at the move and at the push. What flight-rules keeps in a project
moves from `.ai/` to `.flight-rules/`. A first guide ships: `/ux`, read only when an
interface is built or changed.

### Upgrading

**Git hooks changed** — `commit-msg`, `pre-commit`, `pre-merge-commit`, `pre-rebase`,
`post-merge`, `reference-transaction` and `install.sh` — **and there is a seventh,
`pre-push`**. Sync them, as for 0.28.0:
`HOOK_SYNC=auto`, or `install.sh --stale-only`, copies `pre-push` in beside the others,
and `install.sh` now refuses a set without it. The agent guard and the session-start
hooks and the doctor arrive with the plugin.

**What flight-rules keeps in a project moved from `.ai/` to `.flight-rules/`** (#153):
the conf is `.flight-rules/conf`, the committed hook copies are `.flight-rules/hooks/`,
and the default worktree folder is `.flight-rules/worktrees/`. `.ai/skills/`,
`.ai/rules/` and `.ai/master-rules.md` stay where they are. The conf and the hooks
keep working before a project moves: every hook and skill reads `.ai/flight-rules.conf`
where the new conf is absent, `core.hooksPath` goes on naming `.ai/hooks` and the sync
updates the copies there until the moved set exists beside them, and a fresh clone's `install.sh` wires them there. The
worktree folder does not fall back: a project on the default puts its next worktree in
`.flight-rules/worktrees/` (below). To move:

- **The conf**, in two steps, like the hooks: a 0.28.0 hook or plugin reads only
  `.ai/flight-rules.conf`, and finding none falls back to its built-in defaults without
  a word — a custom branch pattern, the note gate, `PROTECTED_BRANCHES=off` undone. On a
  branch, `mkdir -p .flight-rules && cp .ai/flight-rules.conf .flight-rules/conf`, and
  commit both; 0.29.0 reads the new file, 0.28.0 the old. Later, once the committed
  hook copies are 0.29.0's and every clone's plugin is on 0.29.0, on a branch: `git rm
  .ai/flight-rules.conf`. Until then a change to the policy goes in both; the doctor
  says which file it read, and when the two differ.
- **The hooks**, in three steps, so that every checkout runs hooks throughout — the old
  folder's until the setting changes, the moved ones after. `core.hooksPath` is one
  setting for a clone and all its worktrees, and resolves in each. On a branch, `mkdir
  -p .flight-rules && cp -R .ai/hooks .flight-rules/hooks`, commit and merge it; the old
  folder gates that merge. Then, once every checkout and the integration branch have
  the copy — the integration branch merged into each checkout; the doctor names any
  checkout without it, and the integration branch, and prints the command only then —
  in every clone, `git config core.hooksPath .flight-rules/hooks`. A checkout without
  the copy then runs no hooks: the doctor, there or in any other checkout, names it and
  the merge that brings it. Then, on a later branch,
  `git rm -r .ai/hooks`. A clone left naming the old folder — gone, or still there with
  something left in it — is told by the doctor, with the command. A
  `.claude/settings.json` that `exec`s `.ai/hooks/agent/…` is changed with the copy.
- **The worktrees**: a project that sets `WORKTREE_DIR` changes nothing. One on the
  default either sets `WORKTREE_DIR=.ai/worktrees` to stay, or adds
  `.flight-rules/worktrees/` to `.gitignore`; worktrees already made stay where they
  are, and the session-start reminder still lists the merged ones there. The doctor
  says so until `.gitignore` covers the new folder or `WORKTREE_DIR` is set — a ⚠️, so
  to the assistant at session start and on the full report, not on the screen; and
  `/feature-start` names the line when it makes a worktree in a folder not ignored.

**A project with its own `pre-push`** (git-lfs installs one) renames it
`pre-push.local` first. flight-rules' `pre-push` runs it after its own check, with the
same arguments and input, and its exit status decides the push — as `pre-commit` runs
`pre-commit.local`. Until it is renamed, `install.sh` refuses and prints the `mv`, the
sync leaves it alone and names the rename, and the doctor says it does not look like
flight-rules' hook. A first install that finds one in `.git/hooks` names it, with the
way to keep it. The doctor also names a missing `pre-push`, and a `pre-push.local` that
is not executable, which `pre-push` skips without a word.

**Every `pre-merge-check` note made before this release is refused once** (#107). The
note gate now takes a note only when its `passed:` line names the tree of the commit
being merged and it has a `ran:` line. Run `/pre-merge-check` again on any branch
stamped before the upgrade. A developer working alone writes both by hand, with `-f`
over the old note (`hooks/README.md` → `commit-msg` has the command), or goes ahead with
the command the refusal prints, which the merge's trailer records.

**New branches are cut from the local integration branch** (#125), once origin's
commits it lacks are pulled in; before, from `origin/<integration branch>`. A project
that merges only by PR loses nothing: its local branch fast-forwards to origin's. One
that wants branches cut from origin's says so in its own rules, which override; the
hooks' printed routes still name the local branch until a switch exists (#141).

**Rules changed**: `rules/git-worktree-workflow.md`, `rules/multi-ai-setup.md`, and
`rules/engineering-principles.md` — injected into every session — which now opens with
a `trigger: always_on` header for Antigravity (the session-start hook strips it before
injecting), and changes three things an assistant does: it never takes the way through
a stop prints, even when told to go ahead; it does not push to a protected branch
unless the person asks in that session or the project's own written rules do; and a reply that reports work or asks for a
decision assumes the reader remembers none of the earlier context and ends with the
decisions it needs, each decidable alone, last (§7), with no two of its lists sharing a
numbering — the Situation, Background, Assessment, Recommendation headings are this
repo's own convention, not the shipped rule. A project that copied them runs `/rules-sync` to fold the changes in; one
that reads the plugin's copy needs nothing.

**Skills changed**: `/commit`, `/dg`, `/feature-start`, `/pr-create`,
`/pre-merge-check` and `/rules-sync`, and a new one, `/ux`. Plugin users need do
nothing; a project that copied one into `.ai/skills/` runs `/rules-sync`.

**Antigravity users reinstall the plugin** to have the principles loaded into every
session. **Codex users** may add the `SessionStart` entry in README → Consuming. In
neither tool does the doctor run, so the git hooks are wired by hand there; the README
says how.

**What an adopter set that behaves differently:**
- `PR_ONLY_BRANCHES`: a branch it names is no longer deleted by the agent guard, nor
  offered for deletion by `post-merge`, when `PROTECTED_BRANCHES` leaves it out (#128).
  A project that deletes a local PR-only branch on purpose runs the delete itself, or
  sets `PR_ONLY_BRANCHES` so it no longer names it.
- `PROTECTED_BRANCHES=off` (or `none`) also turns off the new warnings. With
  `PR_ONLY_BRANCHES=off`, `main` is warned of as `dev` is, where before nothing was said.
  It does not turn off the agent guard's refusal of a command that sets
  `FLIGHT_RULES_GO_AHEAD`, which holds in any repo, on any branch.
- `FLIGHT_RULES_GO_AHEAD` exported in a shell passes every stop there; the doctor
  reports it as a ❌. Only the value `1` counts.
- `.cursorrules` and `.windsurfrules` are gone from `multi-ai-setup.md`'s layout; a
  project that has them keeps them working. `AGENTS.md` is the one to add, and
  `GEMINI.md` for Gemini CLI.

### Fixed

- **A hand-written note passed the note gate** (#107). It took any note beginning
  `passed:` as proof that `/pre-merge-check` ran, and an assistant wrote that note by
  hand 12 times. `commit-msg` now needs the merged commit's tree on the `passed:` line
  and a non-empty `ran:` line. Otherwise it refuses under "THE NOTE DOES NOT SHOW THE
  CHECK", naming what the note lacks — no tree, a tree that is not a full, lowercase
  hash, no space before `tree:`, or no `passed:` line at all, which before fell through
  to the generic box (#124) — and prints the `/pre-merge-check` route and the one for a
  person working alone. It still cannot tell a hand-written note from a real run: it
  stops the bare shortcut, and a note carried onto a commit it never checked.
  `session-start` and `/feature-start` count a branch as waiting to merge only when the
  gate would take its note.
- **A new branch missed merges not yet pushed** (#125). `/feature-start` cut it from
  `origin/<integration branch>`, so a developer who keeps merges local until a release
  could not branch a fix to one of them. Step 4 now runs `git pull --ff --no-rebase
  origin <integration branch>` in the checkout that has it and cuts from the local
  branch: behind, it fast-forwards; ahead, nothing moves; diverged, it merges its own
  upstream, which `commit-msg` lets through when clean. A merge already in progress
  there stops the step before the pull, as the person's. A pull that fails stops and
  shows git's output; the skill aborts nothing and never stashes or touches the
  person's edits. A branch tracking nothing gets its upstream set first.
- **The route the agent guard and the ref gate print built on a stale base.** The
  guard's refusal of a commit on a protected branch or a branch made in place, and the
  ref gate's refusal on a PR-only branch, printed `git fetch origin` and `git worktree
  add … origin/<integration-branch>`. They now print the base `/feature-start` 4 uses,
  for where the branch is: checked out at the repo root, the pull there; in a linked
  worktree, `git -C <that path> pull …`; missing, `git branch --track` from origin's;
  checked out nowhere, a fast-forward only if origin's has anything new, which git
  refuses when the two have diverged, the branch was never pushed or origin is
  unreachable. The guard reads `INTEGRATION_BRANCH` from the conf, in place of a
  placeholder, and the ref gate now prints the `cd` to the repo root.
- **The printed route is one chain, from its first `cd` to its last**, so a `cd` that
  fails, a fetch with the network down, or any refusal stops it before a branch is cut
  off a stale base or in another repo. It pastes into interactive zsh, the macOS
  default, as into bash: no command row carries a `#` or an apostrophe. It cleans up
  nothing for the person: a failed pull is left to them, and it never says to abort a
  merge. A worktree that held the branch and is gone from its path is named, with
  `git worktree repair` if it was moved and `git worktree prune` if it was deleted, for
  the person to choose — a prune clears every worktree git cannot find, so one that was
  moved lost its staged work. One whose `.git` file alone is missing gets the repair,
  which keeps its staged work. `/feature-start` 4 and the rules say the same.
- **The guard's `python3` fallback ran a project's `json.py`.** With no `jq`, the guard
  parsed its input with `python3 -c`, which imports from the working directory first, so
  a `json.py` in the project ran in place of the standard library's, and every git
  command was then denied as unreadable. It runs `python3 -I` now.
- **The session-start header could arrive garbled** without `jq`, under a non-UTF-8
  Linux locale: `python3` was given it as an argument. It goes on stdin with the rules
  now (#140).
- **`post-merge` printed the feature-merge block on a fast-forward pull of a merged
  PR** (#131), and "Earlier merges left …" on every such pull while cleanup was pending,
  so a project that promotes by PR saw it on every pull. It now reads the reflog: a
  fast-forward prints nothing. The note file is still written.
- **A PR-only branch was offered for deletion, and the guard let the delete through**
  (#128), in a project whose `PROTECTED_BRANCHES` left out `main`, which is PR-only by
  default. `post-merge` now reads `PR_ONLY_BRANCHES` too, so merging `main` in is the
  back-merge it is and prints nothing, and the guard refuses `git branch -d` or `-D` of
  a PR-only branch. Both stand down with `PR_ONLY_BRANCHES=off` or `none`, or
  `PROTECTED_BRANCHES=off`. A `PR_ONLY_BRANCHES` that does not compile keeps every
  branch from deletion until it is fixed, and the guard's block names it. A `main` that neither names is a branch like any other:
  merging it into the integration branch prints its cleanup lines, where before it
  printed nothing.
- **The hook sync told an adopter to mark its own hook adapted.** On a `pre-commit` or
  `pre-push` with no flight-rules marker — a linter's, git-lfs's — `install.sh
  --stale-only` said to add `# flight-rules: adapted`, which would have kept
  flight-rules' hook out for good. It now names the rename to `.local`.
- **`git fetch origin main:main` was refused** (#145) when it brought `main` to exactly
  origin's new commit: the ref gate compared `main`'s new value with `origin/main` as it
  was before the same fetch moved it. It now accepts a value on the upstream's new value
  in that transaction.
- **The doctor read `PROTECTED_BRANCHES=off  # trunk only` and `'off'` as patterns**
  (#127), and beside its ⚠️ that protection was off printed a ✅ about a derived note
  gate; `none` was not handled there. It now reads the conf with the hooks' own reader.

### Added

- **Every stop prints its way through** (#151, #152). The secret scan (a secret found,
  or a scan that could not read), the PR-only gates, the rebase gate and the note gate
  each print `FLIGHT_RULES_GO_AHEAD=1` in front of the command that goes ahead; before,
  the secret scan and the PR-only gates had none, and the note gate's route for a person
  working alone was a note written by hand. Where a refusal leaves an operation
  half-done, the command printed is the one that finishes it: `git commit --no-edit` for
  a merge, `git cherry-pick --continue`, `git am --continue`, `git rebase --continue`,
  `git revert --continue` (a revert of several commits: `git commit --no-edit` first).
  Going ahead is said on the screen every time, with what was passed, and a merge taken
  past the note gate or the instruction check records it in its `Merge-authorisation`
  trailer: past the instruction check, `went ahead (FLIGHT_RULES_GO_AHEAD)`; past the
  note gate, `went ahead with no pre-merge-check note (FLIGHT_RULES_GO_AHEAD)`, or `went
  ahead past the note gate:` and the cause its box named (a note that did not check
  this merge, a catch-up). `pre-commit.local` still runs. The
  instruction check's own route, `FLIGHT_RULES_MERGE_AUTHORISED=1`, is unchanged.
- **The agent guard refuses an assistant's command that sets `FLIGHT_RULES_GO_AHEAD`**
  (#155) — in front of a command, after `env` or `export`, quoted or not — on any branch,
  in any repo, with the branch policy off. The refusal gives the person the command to
  run themselves. Text that names the variable with a value is refused too: the guard's
  accepted trade on prose.
- **`/ux`, a first guide** (#154, #159): accessibility (WCAG 2.2 A and AA, with the
  criteria it does not cover listed), states, forms and basic UX principles, 99 rules in
  four topic files, each labelled a standard, a finding or a rule of thumb, with
  `sources.md` mapping every source to its rules. It loads only the topics a task needs,
  and keeps the project's design record (`.ai/design.md` by default), starting it with
  the project's first interface. A project that never calls it pays only its
  description.
- **`rules/multi-ai-setup.md` principle 6** (#156): where a project names which models
  plan and review and which implement, the planning model stops at the plan, hands the
  work over through an issue carrying it, and reviews what comes back.

- **A warning of a direct change to a protected branch that is not PR-only** (#115,
  #144). A plain commit on `dev` passed every git hook: a probe script that lost its
  `cd` committed on local `dev`, inside a script the agent guard never read. The ref
  gate now warns when such a branch moves to a commit that is not on its upstream, not
  a merge made on it, not a value its own reflog has held, and not on `origin/<a PR-only
  branch>`: a commit, an amend (of a merge too), a cherry-pick, a revert, a squash, a
  fast-forward or `branch -f` onto it. The new `pre-push` warns when a push puts commits
  on a protected branch that no merge brought in, naming up to five and counting the
  rest. Both name the commit and say the move or push goes ahead. A merge, a pull, an
  undo or redo of a local merge, `git fetch origin dev:dev`, a normal push of `dev`
  after local merges, and `/feature-start`'s push of `main` into `dev` say nothing.
  What they do not see — output sent to `/dev/null`, `git push --no-verify`, a branch
  with no upstream, a branch's first push, an amended merge at the push, a remote not
  called `origin` — is in `hooks/README.md`.
- **Codex and Antigravity installs**, in README → Consuming: how to install the plugin
  from a clone, what each gets, and how to wire the git hooks by hand. Antigravity
  converts the plugin and now loads `engineering-principles.md` into every session;
  before, it got the skills and nothing else. Codex runs no plugin hooks; the README
  gives a `SessionStart` entry for `~/.codex/hooks.json` that injects the principles
  from the newest installed version and does nothing without the plugin.

### Changed

- **Where flight-rules keeps its own files in a project**: `.flight-rules/`, not `.ai/`
  (#153) — the conf, the hook copies, the worktrees. `.ai/` is a name another tool, or
  the developer, may already use; what is left in it is the project's own rules and
  skill extensions. The hooks, the skills and the docs name the new places; a refusal
  that says where the policy is set names the conf it read. *Upgrading* has the moves.
  The doctor checks them: a conf or hooks left in the old place, `core.hooksPath` left
  naming `.ai/hooks` however spelled, a pre-conf guard copy in either folder, and a
  worktree folder `.gitignore` does not cover; its update hint names the conf the
  project has. The session-start reminder lists merged worktrees in `.ai/worktrees/` as
  well as the configured folder.
- **`/feature-start`**: step 4 pulls into the local integration branch, as above, and
  step 6 cuts from it. A `hotfix/` branch now needs the person's approval as urgent
  (#143): without it the skill creates nothing and names `fix/` as the route; with it,
  the branch is cut from `origin/main` with `--no-track`, and an issue is filed saying
  it bypassed the integration branch, which its PR links (`/pr-create`).
- **Commit prefixes**: `ci:` is allowed, for a change to the CI; a prefix may carry a
  scope, `fix(hooks):` (#139); and git's own `Revert "<subject>"` passes as it is
  (#136), since the rule's route for a bad merge is a revert. In `/commit`,
  `/pre-merge-check` item 8 and Required 3.
- **`/pre-merge-check`** stamps the tree it checked and one `ran:` line per command,
  with its exit status and last line, single-quoted. Uncommitted changes get a ⚠️ row:
  the stamp vouches for the commit, but the tests ran with those edits on disk. Items 17
  and 18 read `AGENTS.md` beside `CLAUDE.md`.
- **`rules/git-worktree-workflow.md`**: a new section, *Which branch new work starts
  from*, which Required 8 points to; a revert of a merge not yet pushed is cut from the
  local branch, since origin's lacks it (#143); a hotfix only with the person's
  approval, from `origin/main` (#143); Forbidden 1 says how each layer enforces it,
  warnings included; Forbidden 8 says the two clean merges `commit-msg` has always let
  through — a back-merge of a PR-only branch's tip, and the merge of a branch's own
  upstream when the two have diverged — need no instruction and carry no trailer; the
  Enforcement section points at `hooks/README.md` → *Git hooks* in place of a summary
  that still said five hooks.
- **`rules/multi-ai-setup.md`**: the layout's pointer files are `CLAUDE.md`,
  `AGENTS.md`, `GEMINI.md` and Copilot's; `.cursorrules`, which Cursor's docs call
  legacy, and `.windsurfrules` are gone. Gemini CLI reads `GEMINI.md`, not `AGENTS.md`,
  by default.
- **`commit-msg`'s back-merge exemption** no longer looks up `origin` ignoring case.
  A hand-typed `^MAIN$` with a hand-made `MAIN` now lands as a back-merge when origin
  has no `MAIN` or has one holding the commit, and a stale `origin/Main` beside
  `origin/main` no longer blocks a real back-merge of `main`; every state that code
  handled was made on purpose. Under a `GIT_TRACE*` variable, the could-not-check box may
  quote a trace line as git's error.
- **`hooks/README.md`** says the guard's open gap: a redirect written against a git
  word, `git commit>/dev/null`, hides that word from it (#138). 0.28.0 had the same gap.
  The README and `hooks/README.md` lose stale counts and histories the CHANGELOG and
  tests already carry.

### Changed — this repo

- `AGENTS.md` holds how work is done here; `CLAUDE.md` and `GEMINI.md` import it and
  `MISSION.md`. It names this repo's planning and implementing models, and holds the
  Situation, Background, Assessment, Recommendation reply headings §7 no longer ships.
- `MISSION.md`: a stop that prints its way through is not a block, and flight-rules
  never blocks the developer; the person runs the way through, an assistant leaves it to
  them; guides sit beside the core, costing a project that never calls one its skill
  description. The catastrophe of a commit on a protected branch is narrowed to what the
  hooks do: anyone's on a PR-only branch, an assistant's on any; a person's commit on
  another protected branch is warned of, not stopped. It carries no issue numbers.
- `UPSTREAMS.md` pins the sources `/ux` adapts and `ATTRIBUTIONS.md` credits them;
  `/upstream-check` checks a W3C spec or a web page, which has no ref, by its date, and
  judges a change to a `/ux` source rule by rule through `skills/ux/sources.md`.
- A release PR into `main` must carry an `## Upstream check` section and a clean
  mutation stamp of its head commit, written by the new `mutation/` kit and checked by
  CI; the test suites share one harness and had duplicates cut, and each gap the mutants
  found was closed or recorded as a known survivor (`survives: not held` in
  `mutation/mutants.py`).

## 0.28.0 — 2026-10-30

Each refusal, step and rule was re-checked against what flight-rules is for. What had no failure behind it is gone,
what was refused for no reason is allowed, and what a slip could still get through is
closed.

### Upgrading

**Git hooks changed** — `commit-msg`, `pre-merge-commit`, `pre-rebase`, `post-merge`,
`reference-transaction` and `install.sh` — so sync them, as for 0.27.0. The agent guard arrives with the plugin.

**`pre-rebase` now refuses a rebase of every protected branch**, not only a PR-only one
(#118). A project that rebases a protected branch on purpose — its `dev`, say — takes it
out of `PROTECTED_BRANCHES`, and that drops more than the rebase refusal there: the
agent guard's refusal of commits and destructive commands, the `checkout -b` rule, and —
unless `NOTE_GATED_BRANCHES` is set — the `pre-merge-check` note gate, whose default set
is derived from `PROTECTED_BRANCHES`. To keep the note gate, set `NOTE_GATED_BRANCHES`
(`^dev$`, say). A PR-only branch's rebase was refused before and still is. A `git pull`
with `pull.rebase=true` on a branch that is only behind still fast-forwards, and runs
no hook; on one that has diverged from its upstream, the merge the refusal prints, `git
pull --no-rebase`, needs no note when it merges cleanly.

**A merge into `dev` whose conflict was resolved in place is refused now, stamped or
not.** A stamped branch passed as "verified", and a `git merge main` as "already
reviewed", though nothing tested the resolution. A clean merge passes as before. A
conflicted one is resolved on a branch — `dev` merged into the feature branch, or `main`
into a branch cut from `dev` — tested and stamped there, and merged back; the box says
so. The check needs **git 2.38 or later** (`git merge-tree --write-tree`): on an older
git, a back-merge of `main` needs a note, and a stamped merge lands with a warning that
nothing checked it. On a newer git, a merge the check fails on is refused with git's
error and both ways on.

**Rules changed**: `rules/git-worktree-workflow.md`. A project that copied it runs
`/rules-sync` to fold the changes in; one that reads the plugin's copy needs nothing.

**Removed:**
- `rules/dependency-lockfile.md`. A project that copied it keeps its copy; `/rules-sync`
  lists it as local-only.
- `/upstream-check` from the plugin. It checks the sources flight-rules adapts from, so it
  maintains this repo only, and lives here.
- `CLEAR_AI_CONTEXT`. Set, it is ignored: `post-merge` deletes no conversations.

**A project that copied `/dg` or `/pr-create` into `.ai/skills/`** copies the files now
beside them: `dg/pre-review-cli.md`, `dg/comic-page.md`, `pr-create/stacked-prs.md` and
`pr-create/release-pr.md`. `/rules-sync` names each one, with its `cp` command. Plugin
users need do nothing.

**Retired numbers**: `/feature-start` step 2 and `/pre-merge-check` item 16 are retired
and keep their numbers, so the steps after them do too. A project extension that cites
either now points at a retired slot.

### Fixed

- **A rebase of `dev` by hand was refused by nothing** (#118). The agent guard refused
  it, but `pre-rebase` covered PR-only branches only. It now refuses any protected
  branch, read as `commit-msg` reads the pattern, and names the branch even when given
  as `refs/heads/dev` or `heads/dev`. The route it prints is a merge (`git pull
  --no-rebase`), or a rebase of the feature branch. The note gate passes that merge
  without a note when it is git's clean merge of exactly the tip of `origin/<the
  branch>`, its upstream: a branch only behind reaches the same content by a
  fast-forward, with no gate. Before, on a `dev` with local merges not yet pushed, the
  printed route met a second refusal whose route did not fit.
- **A conflict resolved in the merge into `dev` landed untested.** A passing note and
  the back-merge exemption vouched for the incoming commit, not for what the merge
  committed. They, and the new own-upstream exemption, now hold only for git's clean
  merge (`git merge-tree`); the refusal prints the route for a conflict.
- **A plain `git pull` that only caught up was refused as a merge.** `merge.ff false`
  turns it into a merge commit, and the gates refused it with a route for a feature
  merge, under the title "pre-merge check required". They now name it as a catch-up and print `git merge --abort` and `git pull
  --ff-only`. `pull.ff` is not the fix: with it set, `git pull . <branch>` fast-forwards
  the integration branch past the note gate.
- **The note gate's route needed an assistant.** It named only `/pre-merge-check`; it
  now also says what a developer working alone does: run the checks, then record the
  note (flight-rules' `hooks/README.md` has the command; a copy-in project has the hooks,
  not the README).
- **`post-merge` repeated everything on every merge and pull.** After a feature merge
  it prints what that merge left — its worktree, what runs from it, its branch — and one
  line counting what earlier merges left. A pull, a fast-forward or a back-merge prints
  nothing. A back-merge of a released branch not called `main` is recognised too, and
  a merge whose message names no branch (`git merge -m …`) is named by the branch at the
  merged commit. Its note file goes in the clone's `info/exclude` once, so it never shows
  as untracked — unless the project tracks it, when it is left alone.
- **`none` was a pattern to the git hooks.** The agent guard, `session-start`,
  `post-merge` and the doctor read `PROTECTED_BRANCHES=none` as `off` (the doctor
  `PR_ONLY_BRANCHES` and `NOTE_GATED_BRANCHES` too); the git hooks read it as a branch
  name. They now read it as `off` for all three keys.
- **The post-merge note offered `git branch -d main`** as just merged after a back-merge
  of `main`. A protected branch is never listed now.
- **Unstaging and untracking were refused on a protected branch.** The guard now allows
  `git restore --staged` and `git rm --cached` there, in their plain form only (a short
  list of options that touch no file, plain paths, nothing wrapped around them).
- **Dropping a stash was refused on a protected branch, and nowhere else** (#118). A
  stash belongs to the repository, not the branch. The guard no longer refuses it;
  discarding work an assistant did not make still needs a person's yes
  (`engineering-principles.md` → Stops).
- **`/feature-start` pushed to a protected branch.** When `main` held commits the
  integration branch lacked, it ran the fast-forward push itself. It now prints it for
  the person.
- **`commit-msg`'s "who asked" box** has a line for a person merging their own branch.

### Changed

- **Skills stop less.** `/feature-start` notes uncommitted edits in the main checkout in
  one line and goes on, instead of stopping; it no longer stops on a stash. `/pre-merge-check`
  no longer warns above ~20 commits. None had a failure behind it (#119).
- **Skills load less.** What only some runs read now sits in a file beside the skill:
  `/dg`'s contract for a wired pre-review CLI and its comic page, and `/pr-create`'s
  stacked PRs and release steps. A feature PR's `/pr-create` loads 961 words, down from
  1,890; `/dg` loads 3,521, down from 4,168, plus 513 when a wired CLI runs.
- **`/pre-merge-check`**: item 4 type-checks the destination in a detached worktree;
  item 21 stops what the checks or this session started, and names — does not stop —
  anything else.
- **`rules/git-worktree-workflow.md`**: a revert is made on a branch cut from the
  branch being reverted, not in place; a merge into the integration branch is never
  made from a worktree, while merging it into a feature branch belongs there; Required
  8 matches `/feature-start` step 4; its preamble no longer states how the playbook
  re-examines its own advisory items, which is the playbook's policy, not the project's;
  five items — one purpose per branch, the open-branch limit, branch and commit
  prefixes, and reading each commit's diff — now say what goes wrong without them.

### Changed — this repo

- **`MISSION.md`** says what flight-rules is for, and five questions every change to it
  answers. `CLAUDE.md` imports it, and `AGENTS.md` and `GEMINI.md` point other
  assistants at it. It loads only for changes to flight-rules, never in an adopting
  project. `/dg` asks its questions of every change here.
- `CLAUDE.md` records the owner's standing OK for the assistant to merge a stamped
  branch into `dev`; `main` still moves only through the release PR.
- CI's syntax check fails on any broken file, not only on the last one it checked.

## 0.27.0 — 2026-10-24

### Upgrading

**Git hooks changed** — `commit-msg`, `pre-commit`, `pre-merge-commit`, `pre-rebase`,
`reference-transaction`, `post-merge` and `install.sh` — so sync them. With
`HOOK_SYNC=auto` a session's first run does it and leaves the diff to commit — except on
a protected branch, or from a worktree whose hooks are the main checkout's, where it
prints the command to run instead (#99); with the default `report`, doctor names each
stale copy and prints the command. From this release
on, the automatic sync never replaces a copy that is a newer release's than the one
syncing. A session still on 0.26.x has an installer without that check: left open, it
can write its older copies back over newer ones on its first session start each day,
until it is closed, and the next current session's daily check restores them. Close
sessions on older versions after updating.

**After `/plugin update` and `/reload-plugins`**, the next prompt now says the session is
on the new version and that a new session loads its rules and runs the checks (#94). It
comes from the plugin's own wiring (`hooks.json` passes `--plugin`); hand-wired setups
get no such notice and need no change. A session already open when 0.27.0 arrives is not
told: the version it started on was never recorded.

**A full install no longer overwrites a project's own hooks** (#97). Before, only
`pre-commit` was protected. It tells them apart by a phrase each flight-rules hook
carries — a heuristic: a project's own `pre-commit` that mentions `PRIVATE KEY` is still
taken for flight-rules' and replaced (#113). And when the install points git at flight-rules' hooks
folder, it names any hooks git will stop running from `.git/hooks/` or a global hooks
folder; running them alongside flight-rules' is #111.

**The post-merge cleanup list looks different** (#109): it is printed at the merge, not
only written to `.claude/post-merge-note.md`; names that need quoting are in `'…'` (plain
ones are bare); and an annotation such as `↑ just merged` sits on its own line.

One new key in `.ai/flight-rules.conf`, `OPEN_BRANCH_LIMIT`, **on by default at 5**: with
five branches open, `/feature-start` asks before opening a sixth, and run with no one to
ask, it opens none. `off` turns it off. Below.

### Added

- **Open-branch limit** (#108). At `OPEN_BRANCH_LIMIT` branches open and not yet merged
  into the integration branch, local or `origin/`, session start warns — on screen and to the assistant,
  naming which have passed `pre-merge-check` and wait to merge — and never blocks.
  `/feature-start` counts before opening another and, at the limit, opens it only once
  you say it is okay, naming where the limit is set; the guard's suggested commands and
  this repo's CLAUDE.md point at it, since a raw `git worktree add` skips the count. `off` stands both down. A count
  that cannot be made (no integration branch, a git failure, a protected pattern that
  does not compile) is said to the assistant, never read as "under the limit".
- **What testing started is stopped** (#109). The post-merge list names processes still
  running from each merged worktree — by working directory or a path in the command
  line — and Docker Compose containers started from it (`docker ps -a`, bounded to 3 s;
  silent without docker, said when docker fails). It stops nothing. `pre-merge-check`
  item 21 asks that what a branch's checks started is stopped before the stamp.
- **`/dg` Review Domains** (#96): the classes a reviewer is asked to look for —
  authorisation, untrusted input, fail-open defaults, races, magic values, swallowed
  errors, time, unbounded work, compatibility, tests — reach every reviewer's brief on
  code.
- **`pre-merge-check`**: item 4 gates new type errors against the destination's set;
  item 20 flags swallowed errors.

### Fixed

- **Hook downgrade**: the automatic sync took any release's exact copy as replaceable,
  so a session on an older version replaced newer hooks with its own (batch review).
  Doctor also called a newer copy "behind" and pointed at a command that downgraded it;
  it is now a ⚠️ that says a newer session wrote it.
- **Pasting the cleanup list could run code** (#109 reviews): git allows `'`, `;`, `$`
  and backticks in a branch name, and the list printed names raw — in its commands and
  on every other line. Every value from outside the hook is now quoted, with one shared
  quoting function (`shq`, kept identical in the four scripts that print commands to
  paste, and tested), which also fixes `printf %q` on macOS bash 3.2 splitting
  non-ASCII names. A process row forged by a newline in a command line is dropped.
- **A protected-branch pattern that does not compile protected nothing** (#103): the
  guard and the gating git hooks now treat it as protecting every branch, say so, and
  print a way out that works from where the refusal leaves you (`post-merge`'s cleanup
  list offers nothing for deletion and does not say why, #113). A pattern that gates matches
  case-insensitively, as the guard's does; one that exempts — a back-merge of a PR-only
  branch — takes the pattern's exact case, and every case variant of the branch on
  origin must hold the commit; a refusal lists those that do not, judging none of them.
- **The secret scan skipped a merge's concluding commit** (#101), the hand-written
  conflict resolution included; it now scans what the resolution adds — the agent guard
  as git's hook does, where it had scanned every incoming commit and refused the commit
  that finishes a refused merge — worked out with `git merge-tree` where git wrote no
  `AUTO_MERGE`; with git older than 2.38, or for an octopus merge, everything staged is
  still scanned. Mid-merge, neither refusal says to unstage a file: the merge would keep
  `HEAD`'s copy and drop the incoming change.
- **The merge-authorisation box printed a `git merge` that always failed** (#100) while
  the refused merge was still in progress; it prints the command that concludes it. The
  note gate's, PR-only merge and rebase refusals print no bypass any more: theirs failed
  mid-merge, or met the ref gate wherever origin has the branch, and one that worked
  would hand an assistant the skip the gate exists to stop.
- **`HOOK_SYNC=auto` wrote into a checkout on a protected branch** (#99), leaving a diff
  nobody could commit; there it now only compares and prints the command for a branch —
  mid-merge, -rebase or -bisect too, when the command is for afterwards.
- **The guard's branch policy could switch off** when the project directory was a symlink
  to a subdirectory of its repository with the link itself inside another repository,
  or when the shell exported a `CDPATH` that `cd .git` could resolve through (one
  holding `.`, or naming a directory with its own `.git`, such as a dotfiles home): it
  took the project for a different repository and allowed a commit on a protected
  branch. It now finds the project as git does.
- **`install.sh` read `--from` and the hooks path by name**, so a `..` after a link named
  a different directory from the one git uses, and an exported `CDPATH` could misread
  them too; it now walks them as the kernel does.
- **The guard looked for `MERGE_HEAD` in its own working directory**, not the `-C`
  target (#98): a false block from a worktree, and a waiver that leaked across repos.
- **`HOOK_SYNC=auto` warned daily in every worktree whose hooks live in the main
  checkout** (#93), even with nothing stale; it compares first and is silent when current.
- **Doctor did not report a stale `.ai/hooks/install.sh`** (#90).
- **Session start and `post-merge` read a quoted conf value with its quotes** —
  `INTEGRATION_BRANCH='dev'`, `WORKTREE_DIR`, `HOOK_SYNC='auto'` — while doctor showed ✅;
  a quoted `PROTECTED_BRANCHES` had `post-merge` offer `git branch -d main` as safe to
  delete. Both read them as the guard does, `post-merge` with
  `FLIGHT_RULES_PROTECTED_BRANCHES` first. Doctor's own branch helpers still keep a
  single-quoted value's quotes (#113).
- **Session start in a subdirectory found no conf**, so `HOOK_SYNC`, the open-branch
  count and the branch parameters went to their defaults unsaid; it reads the
  checkout's top, and `FLIGHT_RULES_WORKTREE_DIR` first, as the guard does.
- **`/feature-start` stopped every branch as "diverged"** in a project that promotes by
  PR: `main`'s merge commits are not a divergence when merging `main` in changes no file.
- **The ref gate's way out branched off the PR-only branch**, into `.ai/worktrees`
  whatever `WORKTREE_DIR` said; it now starts from `origin/<integration branch>`, in
  `WORKTREE_DIR`, quoted to paste, as the guard's does. `pre-merge-commit`'s PR route
  names the integration branch for a feature.

### Changed

- **`/dg` output order**: header, comic, rounds, verdict, then the decisions waiting — a
  numbered list, not a table — so they are where a terminal leaves the reader. The skill
  names it as its one departure from the principles' "lead with what needs deciding".
- **`/dg`**: an extension's own pre-reviewer timeout is an inner limit under
  `DG_WAIT_MINUTES` (#95). The release-review check's three known Markdown limits are
  accepted rather than parsed further (#91).
- **Principles**: a refused command may go to the person, told it was refused, by what
  and why — an ask that carries its reasons, and never a hand-written `pre-merge-check`
  note; a command you need the person to run is a decision you ask for, with what waits
  on it and how many such asks are open; the UTC line moved to the checklists.
- **READMEs**: flight-rules assumes a competent developer and does not babysit.

## 0.26.0 — 2026-10-20

### Upgrading

No git hook changed, but `install.sh` did (#87), and the hook sync carries it. With
`HOOK_SYNC=auto`, a session replaces an unmodified `.ai/hooks/install.sh` and leaves the
diff for you to commit. Where that happens depends on `core.hooksPath`, which
`git config --local core.hooksPath` shows:
- A relative path, which every install since 0.24.0 writes: each checkout's session
  syncs its own copy, worktrees included.
- An absolute path into the main checkout, which 0.23.0 and earlier wrote: only a
  session there syncs. A session in a worktree prints the command to run there, every
  day, even when nothing is stale (#93).
- An absolute path outside the repository: never synced; the session says so.

No sync runs while a merge, rebase or similar operation is in progress, and the session
says so. A copy you changed is left alone. The session names it only when another hook
is synced in the same run, which happens for a project older than 0.25.0, whose
`pre-commit` changed then. It also lists it among uncommitted changes while it is
uncommitted. With the default `report` nothing is said at all, because doctor checks
only the hooks themselves (#90). An old or changed copy still works. To see where yours
stands, or to update an unmodified one, run this from the checkout `core.hooksPath`
points into, where `<plugin>` is
`~/.claude/plugins/cache/<marketplace>/flight-rules/0.26.0`:

```bash
bash <plugin>/hooks/git/install.sh --from <plugin>/hooks/git --stale-only
```

One new optional `.ai/flight-rules.conf` key, `DG_WAIT_MINUTES`, is described below.

### Fixed

- **`/dg` lost the pre-review when the debate finished first.** Round 1 started only
  after the pre-reviewers had been launched, and nothing made a later round wait for
  them. A pre-review left running in the background finished after the verdict, and
  its findings reached no round (2026-10-18). Now round 1 starts in the same turn as
  the pre-review and the dependency scan, and stays blind to both. Round 2 waits for
  every pre-reviewer and the scan to finish or fail, then answers each of their
  findings. The debate can no longer converge before round 2. Each run gets
  `DG_WAIT_MINUTES`, new in this release (default 15), from its own start. A run with
  no result by then counts as failed. A cross-family run that times out starts the
  same-family fallback, which gets its own `DG_WAIT_MINUTES`, so round 2 can wait about
  twice the setting. If that run also fails, the result is reported
  `⚠️ unavailable — no result in <n>m`.
  `flight-rules-doctor.sh` warns on a value that is not a positive whole number.
  Untested beyond reading: a `claude plugin eval` case did not reproduce the race
  headlessly (#89).
- **Doctor warned "no agent guard wired" in every worktree of a project that enables
  the plugin in `.claude/settings.local.json`** (#88). That file is git-ignored, so
  only the main checkout has it. A probe on 2026-10-19 showed Claude Code applies the
  main checkout's copy to sessions in linked worktrees, so the warning was false.
  Doctor now reads the main checkout's file too.
- **A full copy of a skill escaped doctor's shadow warning by mentioning the plugin
  in passing** (#82). A same-named command or skill was exempt if it contained
  `skills/<name>/SKILL.md` or `flight-rules:<name>` anywhere. It is now exempt only
  if a line starts with one of the two real pointer shapes:
  - ``Read and follow `…skills/<name>/SKILL.md` ``
  - ``Use the `flight-rules:<name>` skill``

  A wrapper worded any other way now gets the warning. Read it before changing
  anything. A command nested in `commands/<dir>/` is still not checked, because it
  registers as `/<dir>:<name>` and leaves `/<name>` to the plugin (probe, 2026-10-19,
  #85).
- **From a linked worktree, `install.sh --stale-only` said the hooks were "outside
  this repository; sync it by hand"** (#87). This happened when `core.hooksPath` was
  the usual absolute path into the main checkout, and it is what `HOOK_SYNC=auto`
  printed in every worktree session. The hooks are still not synced from a worktree,
  because the write would land in another checkout's working tree. The message now
  names the main checkout and prints a `cd <main> && … --stale-only` command that
  works when pasted. Its paths are quoted for the shell, so a path containing `$(…)`
  does not run that command when pasted. The same goes for the command
  `HOOK_SYNC=auto` prints after skipping a sync while a merge, rebase or other
  operation is in progress; since 0.25.0 that command wrapped its paths in `"…"`. It
  also goes for the `mv -n` rename `install.sh` prints when your own pre-commit is in
  the way; that one wrapped its paths in `'…'` and is now on a line of its own.

### Changed — this repo's release PRs

- The `release review` check now also requires a `### Verdict` heading in the
  **Adversarial review** section (#83), with text under it that is not a heading.
  The `> Pre-review:` line alone used to pass. A line like `#83 applied` counts as
  text, not as a heading. A heading indented by up to three spaces counts as a
  heading, apart from the `## Adversarial review` line itself, which must start the
  line. An H1, and a `##` followed by a tab or by nothing, end the section. Inside a
  code fence, a `### Verdict` is not the verdict, and a `## ` line does not end the
  section. The check also fails when it cannot count the section, instead of passing.
  Its known limits are listed in the workflow's comment (#91).
- Only the `pr-create` template's own placeholder lines (`<the …>`, `<ONLY if …>`)
  count as empty. A review written as one-line HTML used to count as empty (#84).
- `docs-consistency.test.sh` now also checks three things:
  - every Markdown code fence is closed (#86);
  - every conf key doctor knows has a row in the Configuration table;
  - `DG_WAIT_MINUTES` has a single default across the skill, doctor and the docs.

## 0.25.0 — 2026-10-17

### Upgrading — sync the git hooks; this one is a security fix

`hooks/git/pre-commit` changed, and a plugin update cannot touch your project's git
hooks. With `HOOK_SYNC=auto` the first session after the update syncs them (unless a
merge, rebase, `git am`, cherry-pick, revert or bisect is in progress, which it now says). With
the default `report`, doctor names the stale hook and prints the command:

```bash
bash <plugin>/hooks/git/install.sh --from <plugin>/hooks/git --stale-only
```

Then commit the diff. Doctor may also warn, new in this release, that a command or skill
of yours shadows a flight-rules skill — read the warning before deleting anything.

### Fixed

- **A ref named `MERGE_HEAD` switched the secret scan off.** `pre-commit` skips its scan
  while a merge is being concluded, and decided that with `git rev-parse --verify
  MERGE_HEAD` — which also resolves a branch or tag of that name. With one, every commit
  went unscanned and nothing was said; a staged AWS key committed (AppliHawk's security
  review, 2026-10-17, reproduced). 0.25.0 tests git's `MERGE_HEAD` file, skips only
  when it names a commit `HEAD` lacks — a leftover naming `HEAD` or an ancestor makes
  an ordinary commit, and is scanned — and prints "secret scan skipped" every time it
  skips, so a leftover file is seen too. The message names the commit being merged in, says
  the commit records it as a parent, and says to check `git log -1` and `git status`; it
  prescribes no command, since it cannot tell a leftover from a real merge and each one
  offered during the release review was wrong in one of them. The merge gate's refusal
  box still offers `git merge --abort` for a refused merge, and now says it also drops
  what you staged and that a merge you never started is a leftover.
  `session-start.sh` had the same lookup for `MERGE_HEAD`, `CHERRY_PICK_HEAD` and
  `REVERT_HEAD`: a ref so named skipped `HOOK_SYNC`; it tests the files now.
- **A leftover `REBASE_HEAD` blocked `HOOK_SYNC=auto` for good, silently.** git leaves
  that file after some rebases; AppliHawk's dated from March 2026, so under 0.24.1 its
  hooks never synced and nothing was printed while doctor called them stale. A rebase in
  progress is the `rebase-merge` or `rebase-apply` directory, which was already checked.
  The sync now also waits out a stopped `git am` (named as such, not "a rebase") and a
  half-done multi-commit cherry-pick or revert (`sequencer/todo`) and a `git bisect`,
  and every skip says why, with the command to run once it is finished.
- **A headless session spent the day's on-screen message.** The first session each day
  set the flag even when it was `claude -p` — a scripted `/dg` pre-review, CI — so that
  day's doctor ❌ reached no screen and the attended sessions after it stayed quiet.
  With `CLAUDE_CODE_SESSION_ATTENDED=0` (set by `claude -p`; observed on Claude Code
  2.1.301, undocumented) doctor still runs but the flag is left, so headless sessions
  run it until an attended session has that day. Unset keeps 0.24.1's behaviour. A headless session still syncs the
  hooks under `HOOK_SYNC=auto`, so the clone is protected at once; its "commit the
  diff" reached no screen, so an attended session now says on screen when the hook
  directory has uncommitted changes (yours count too).

### Added

- **Doctor names a command or skill that shadows a plugin skill.** A
  `~/.claude/commands/dg.md` (or a project `.claude/` one, or a skill of the same name)
  is what `/dg` runs; AppliHawk's, a copy from 2026-06-11, ran in place of every later
  `/dg` with nothing said. A pointer at `skills/<name>/SKILL.md` or a wrapper that hands
  over to `flight-rules:<name>` is not a shadow.
- **`/dg` dependency CVE scan**, from upstream dinesh-gilfoyle: the ecosystem's own audit
  where installed, else OSV.dev, at the reviewed head. It reaches the network, says so,
  and can be declined; it never installs a tool, and a scan that did not run is reported
  "not run", never clean.
- **`/dg` banter score and comic strip**, from upstream. Every verdict now reaches you
  and ends with the comic drawn as text, and `/dg` stops there: nothing is applied, even
  inside `pr-create` 2b, until you reply. Upstream offers the comic instead, and this
  release's own review skipped that offer. The comic is ASCII art and holds the banter
  score. Two settings in `.ai/flight-rules.conf` control it per project: `DG_COMIC`
  (`always`, the default, or `never`) and `DG_COMIC_PR` (`never`, the default, `ask` or
  `always`) for whether a PR gets the comic and its score — strictly opt-in; this repo
  sets `always`. `flight-rules-doctor.sh` checks both values. A PR body never carries
  the round tables' banter, except as the opt-in comic's quotes.
  An HTML page or PNG of the comic is made only on request and stays local; every value
  in the page is escaped and the template carries a Content-Security-Policy. `/rules-sync` now
  reports a copied skill's missing companion files with the `cp` that adds them, so a
  project that copied `/dg` in learns it lacks the template.

### Changed — `/dg`

- Round 1 is blind: the pre-review reaches the personas from round 2.
- Personas are told research only, do not edit; Gilfoyle no longer must find a
  critical or important issue.
- Finding tables carry Location, and persona tables Verified? and Fix.
- An empty `/dg` also reviews untracked files.

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
