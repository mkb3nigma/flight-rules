# Changelog

What changes for someone who installs a new version — behaviour first, because that is
what arrives without being asked for. Each entry says what the old version did and what
this one does; every verdict below was run against both, not reasoned about.

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
