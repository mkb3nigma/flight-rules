---
name: upstream-check
description: Check whether the external sources this playbook adapts from (tracked in UPSTREAMS.md) have new changes worth folding in. Review-and-fold — never auto-applies.
---

# /upstream-check — Check Upstream Sources for Updates

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

## Step 3 — Report
Per source:
```
dinesh-gilfoyle (feeds skills/dg/)              ⬆ 4 new commits since <pin>  <compare-url>
andrej-karpathy-skills (feeds engineering-…)    ✔ up to date (<pin>)
karpathy LLM-wiki gist (docs-lint concept)      ⬆ new revision — review manually
```

## Step 4 — Fold in, then re-pin
For each source with updates:
1. Review the upstream changes at the compare link.
2. Fold in anything worth adopting to the corresponding flight-rules file(s) — by hand,
   preserving this repo's own modifications and honouring the upstream licence.
3. If the nature of the adaptation changed, update `ATTRIBUTIONS.md`.
4. **Re-pin**: update the row's ref to the new upstream HEAD and bump the pin date in
   `UPSTREAMS.md`, so the next run measures from here.

Never auto-apply upstream content. The output is a review list plus, on request, help
folding specific changes in.

> This checks the playbook's **upstream** provenance. For a project syncing its local
> copies **downstream** from the playbook, use `/rules-sync`.
