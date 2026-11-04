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

Before every `dev` → `main` promotion (#132), on the commit being promoted. It takes
hours, so it is not a per-branch check, and it is not one of `{TEST_COMMANDS}`.

## How to run it

```bash
mutation/run.sh -j 4           # all of them; -j sets how many run at once
mutation/run.sh P01 C49 S010   # some of them, by id
```

Every mutant runs in its own copy of the tree, made once at the start without `.git`
or `.ai/worktrees`; the checkout is only read. Before any mutant, each suite in use runs
unmutated and must pass. A suite run is cut off after `MUTATION_TIMEOUT` seconds
(default 1200) and counted as a kill. The run ends with a summary — killed by suite,
the survivors, what did not apply — and the work directory, whose `logs/` hold every
suite's output.

Exit 0: every mutant expected killed was killed, and every mutant applied. Exit 1: one
survived that should not have, or one's `old` text did not occur exactly once — an
error, never a skip. Exit 2: usage, or a suite failing with no mutant applied.

More than about six suites at once and `merge-gate.test.sh` fails cases that have
nothing to do with the mutant, which reads as a kill: the sweep recorded eight such on
commit-msg, post-merge and pre-commit mutants, and each survives run alone. Keep `-j` at 4 or so; a surprise in
either direction is run again alone before it is believed.

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
