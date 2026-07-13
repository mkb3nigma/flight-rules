---
name: docs-lint
description: Health-check the project's living docs — find contradictions, stale claims, orphaned references, and index/detail drift. Read-only report; fixes are a separate step.
---

# /docs-lint — Living-Docs Health Check

> Adapted from the *lint* operation in Karpathy's
> [LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) pattern:
> knowledge bases rot through bookkeeping neglect, and bookkeeping is what AI is for.

## Invocation

```
/docs-lint                # lint the project's planning/status docs
/docs-lint <dir or file>  # lint a specific scope
```

## What counts as "living docs"

Status trackers, checklists, roadmaps, runbooks, plan files, README setup sections,
rules files, and any AI-memory index — documents that claim to describe *current*
state. (Not: archived reviews, changelogs, or anything explicitly historical.)

## Checks

1. **Internal contradiction** — a summary table and its detail sections disagree; two
   docs state different statuses/values for the same item.
2. **Staleness against ground truth** — spot-check claims that are cheap to verify:
   "file X doesn't exist" (does it?), "N tests passing" (per the latest run?),
   "branch Y pending merge" (`git branch --merged`), "❌ not created" for things
   present in the tree.
3. **Orphaned references** — links/paths to files, branches, scripts, or sections that
   no longer exist; cross-references (`[[name]]`, relative links) that resolve nowhere.
4. **Dead decisions** — instructions contradicting a later recorded decision
   (e.g. a doc still says "merge after ad partner is decided" after ads were killed).
5. **Date drift** — "Last Updated" headers older than the newest substantive edit
   (`git log -1 --format=%cs <file>`).
6. **Duplicate truth** — the same fact maintained in ≥2 places with no pointer;
   propose a single home + references.

## Output

A findings table — `| # | Doc | Finding | Evidence | Suggested fix |` — ordered by how
misleading the error is to a cold reader (a wrong status beats a stale date). End with
a one-line verdict: `CLEAN` or `N findings (M misleading)`.

**Read-only by default.** Apply fixes only on explicit request, as a normal docs
change on a branch per the project's workflow.

## Cadence

Run after any milestone that changes many statuses at once (a review wave, a merge
batch, returning to a project after weeks away) — that's when drift is born.
