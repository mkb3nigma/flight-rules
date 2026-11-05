# Mutation kit

The suites say the hooks work; this checks that the suites would notice if they did
not. Each mutant in `mutants.py` breaks one decision in a hook, a wiring file or the
release-review workflow — a refusal that exits 0, a pattern that never matches, a flag
dropped — and `run.sh` runs the suites that should notice. A mutant is **killed** when
one of them fails (an abort, exit 2, counts and is shown as one), and **survives** when
all pass: a guard the tests do not hold.

It began as the 2026-11 test sweep's three kits and the targeted mutants after them,
merged here, re-anchored on text and pruned to one mutant per distinct guard or
decision.

## When it runs

Before every `dev` → `main` promotion, on the commit being promoted (`AGENTS.md` →
*Releasing*); and before a major change merges into `dev`, when the owner calls for it
(owner, 2026-11-04). It takes hours, so it is not a per-branch check, and it is not one
of `{TEST_COMMANDS}`.

For a release, its summary line goes under `## Mutation run` in the promotion PR, and
the `release review` check refuses the PR unless that line is of the whole kit
(`mutation: all <n> run from …`; a selection prints `<n> of <total>`), is clean — no
unexpected survivor, nothing that failed to apply — and names the PR's head commit with
no tracked file changed (owner, 2026-11-05). Pasted plain, in backticks, as a list item
or a quote, it reads the same. A commit pushed after the run means running it again.
Run it from a worktree of that commit, so nothing else in a checkout is in the way:

```bash
git worktree add --detach .ai/worktrees/mutation <sha>
cd .ai/worktrees/mutation && mutation/run.sh -j 4
```

The gaps the suites are known to leave — the `survives: not held` mutants — are #133: a
release run passes with them, and fails on any new one.

## How to run it

```bash
mutation/run.sh -j 4           # all of them; -j sets how many run at once
mutation/run.sh P01 C49 S010   # some of them, by id
```

Every mutant runs in its own copy of the tree, made once at the start from the files
git tracks, as they stand — an untracked file is neither copied nor counted, and a new
one is in once `git add`ed; the checkout is only read. A tracked file that differs from
the commit is named at the start, with the route above, and marks the summary line
"+ uncommitted changes". Before any mutant, each suite in use runs unmutated and must
pass. A suite run is cut off after `MUTATION_TIMEOUT` seconds (default 1200) and
counted as a kill. The run ends with a summary — killed by suite,
each abort and timeout by id with the line it failed on, the survivors, what did not
apply — and the work directory, whose `logs/` hold every suite's output.

Exit 0: every mutant expected killed was killed, and every mutant applied. Exit 1: one
survived that should not have, or one's `old` text did not occur exactly once — an
error, never a skip. Exit 2: usage, or a suite failing with no mutant applied.

More than about six suites at once and `merge-gate.test.sh` fails cases that have
nothing to do with the mutant, which reads as a kill: the sweep recorded eight such on
commit-msg, post-merge and pre-commit mutants, and each survives run alone. So with
`-j` above 1, every kill by an abort, a timeout, merge-gate, or a case with a time bound
is run again alone, and counts only if it repeats; one that does not is named in the
summary. That adds about two hours at `-j 4`. Keep `-j` at 4 or so.

## Upkeep

- **A hook edit that moves a mutant's anchor updates that mutant in the same change.**
  `python3 -I mutation/mutants.py check .` says which no longer occur exactly once.
  A mutant whose target is gone is deleted with it.
- A mutant expected `killed` that survives is a gap in the suites: close it there, not
  by changing the expectation. `survives: not held — <what>` marks a gap the suites are
  known to leave; a test that closes one makes the run say so, and its expectation
  becomes `killed`. A mutant equivalent to the hook (no behaviour a test could see) is
  deleted, not kept as a survivor.
- Add a mutant for a new guard or decision, not a second one for a guard already held.
- Nothing here is named `*.test.sh`: `docs-consistency.test.sh` would take it for a suite.
