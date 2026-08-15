---
name: upstream-check
description: Check whether the external sources this playbook adapts from (tracked in UPSTREAMS.md) have new changes worth folding in, and sweep for adapted sources that were never recorded. Review-and-fold — never auto-applies.
---

# /upstream-check — Check Upstream Sources for Updates

## Project extensions

Before executing, check the consuming project for `.ai/skills/upstream-check/EXTENSIONS.md`.
If present, read it first: it supplies the project's `{PLACEHOLDER}` values, plus any
additional or replacement steps and project-specific rules — extensions take
precedence over the generic defaults below. If absent, use the defaults as-is.

flight-rules is **downstream** of a few third-party works — the dg persona, Karpathy's
LLM-pitfalls principles, and others (see `ATTRIBUTIONS.md`). Those upstreams keep
evolving. This skill checks each tracked source for changes since the ref we last
reviewed, so improvements can be **manually folded in** (licences and wording differ —
this is never an automatic merge).

Run this **inside the flight-rules repo** (it's a maintainer skill, not a per-project one).

---

## Step 1 — Read the sources manifest
Read `UPSTREAMS.md`. Each row is one source: name, repo/URL, which file(s) it feeds, the
**pinned ref** we last reviewed against, and the pin date. This manifest is the single
place new external references get added, so this skill scales as sources are added.

## Step 2 — Check each source for changes
For a git repo:
```bash
git ls-remote <repo-url> HEAD        # current upstream HEAD
```
Compare the returned SHA to the row's pinned ref.
- **Equal** → up to date.
- **Different** → there are new commits. Build a compare link:
  `https://github.com/<owner>/<repo>/compare/<pinned-ref>...<current-head>`
  and (if the API is reachable) summarise the commit subjects since the pin.

For a **gist** (e.g. the docs-lint concept source), there is no branch HEAD — open the
gist's *Revisions* tab and compare against the pinned revision/date.

If the network is unavailable, say so per source rather than reporting a false
"up to date".

## Step 2a — Sweep for sources that were never recorded
Steps 1–2 can only check sources the manifest already knows about. They verify that
known pins haven't moved; **nothing verifies the manifest is complete**, so a source
that was never written down is invisible to the exact mechanism built to track sources.
That is not hypothetical — `skills/diagnose/` went from 2026-06 to 2026-08 uncredited
because the borrow was recorded in the source project's commit message and lost in
transit (see `ATTRIBUTIONS.md`).

Sweep the history of **this repo and any project a skill was distilled from** for
borrow language, then check each hit against `UPSTREAMS.md`:

```bash
git log --all --format="%h %ad %s%n%b" --date=short |
  grep -iE "borrowed|adapted from|derived from|inspired by|based on|ported from|credit to"
```

Also grep the working tree — some credits live only in a file's own prose:

```bash
grep -rniE "adapted from|derived from|inspired by|borrowed from" \
  --include="*.md" . | grep -v ATTRIBUTIONS.md
```

Expect noise — these are broad word patterns, and a hit is a lead, not a finding. On a
real run against this repo they included a naming homage ("borrowed from NASA's *flight
rules*"), an incidental use of the words ("derived from the branch name"), and this
skill matching its own grep patterns. Triage each hit to the ones naming an **external
work whose ideas or text were adapted**, then check those against `UPSTREAMS.md`.

For every source that survives triage and has **no `UPSTREAMS.md` row**: report it as a
provenance gap, not as an update. The fix is an `ATTRIBUTIONS.md` entry plus a row — see
Step 4's pinning rule, which matters more here than anywhere else.

Report a clean sweep explicitly ("no unrecorded sources found"). Silence reads as
"not checked".

## Step 3 — Report
Per source:
```
dinesh-gilfoyle (feeds skills/dg/)              ⬆ 4 new commits since <pin>  <compare-url>
andrej-karpathy-skills (feeds engineering-…)    ✔ up to date (<pin>)
karpathy LLM-wiki gist (docs-lint concept)      ⬆ new revision — review manually
mattpocock/skills (feeds skills/diagnose/)      ⬆ 323 new commits since <pin>  <compare-url>
```

Then the Step 2a sweep, as its own line — a gap is a different class of finding from an
update and should not be buried among them:

```
Provenance sweep: no unrecorded sources found.
   — or —
⚠ PROVENANCE GAP: <source> named in <commit/file> has no UPSTREAMS.md row.
```

## Step 4 — Fold in, then re-pin
For each source with updates:
1. Review the upstream changes at the compare link.
2. Fold in anything worth adopting to the corresponding flight-rules file(s) — by hand,
   preserving this repo's own modifications and honouring the upstream licence.
3. If the nature of the adaptation changed, update `ATTRIBUTIONS.md`.
4. **Re-pin**: update the row's ref to the new upstream HEAD and bump the pin date in
   `UPSTREAMS.md`, so the next run measures from here.

**Pin what you reviewed, never what is newest.** A ref is a claim that everything up to
it has been read. When adding a row for a source found by the Step 2a sweep, pin it at
the source's state *when the adaptation was made* — dig that out of the borrowing
commit's date if nothing better exists — and leave it deliberately stale so the next run
flags it. Pinning a newly-found source at HEAD converts an unreviewed backlog into a
green "up to date" in one move, which is worse than having no row at all: the gap
becomes invisible *and* looks audited.

Never auto-apply upstream content. The output is a review list plus, on request, help
folding specific changes in.

> This checks the playbook's **upstream** provenance. For a project syncing its local
> copies **downstream** from the playbook, use `/rules-sync`.
