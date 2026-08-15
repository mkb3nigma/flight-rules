# Attributions

This playbook stands on other people's work. Original content here is MIT-licensed
(see LICENSE); the portions below are adaptations of third-party works and remain
subject to their upstream licenses.

The **sync state** for these sources — which upstream ref each adaptation was last
reviewed against — is tracked in [UPSTREAMS.md](UPSTREAMS.md); run `/upstream-check`
to see what has moved since.

## skills/dg/ — adversarial review

Derived from **[dinesh-gilfoyle](https://github.com/v1r3n/dinesh-gilfoyle)** by
**[@v1r3n](https://github.com/v1r3n)**, licensed under
**[Apache License 2.0](https://github.com/v1r3n/dinesh-gilfoyle/blob/main/LICENSE)**.

Modifications in this repo: condensed the persona definitions; generalized the review
domains beyond code (architecture, product/business, decisions); added the optional
independent pre-review stage, convergence handling, and the merged-verdict output
format; parameterized project-specific behavior into local-extension sections.

## rules/engineering-principles.md — principles 1–4

Adapted from **[andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills)**
by **multica-ai**, licensed under
**[MIT](https://github.com/multica-ai/andrej-karpathy-skills/blob/main/LICENSE)** —
itself derived from **Andrej Karpathy's** public observations on LLM coding pitfalls.

Modifications in this repo: restructured into the current six-principle format,
reworded bullets, and merged or dropped the ones that restructuring made redundant.
Principles 5 and 6 do not come from this source — see below.

## rules/engineering-principles.md — principle 5 — concept credit

Principle 5 ("Suggest Better Ways") is owed to **an unnamed Reddit post** — unnamed
because neither the author nor the link was recorded at the time, not because the
author posted anonymously. The observation was that an assistant staying quiet about a
better approach is itself a failure mode. The wording here is original; the insight is
theirs. If the post resurfaces, credit the author and add the permalink here. There is
nothing to track for updates, so this source has no [UPSTREAMS.md](UPSTREAMS.md) row.

Principle 6 ("Judge Ideas on Their Merit") is original to this repo and MIT-licensed
like the rest. It is called out only because both of its neighbours are not.

## skills/diagnose/ — concept credit

The diagnosis loop — reproduce → minimize → hypothesize → instrument → fix → verify →
clean up, with tagged instrumentation so cleanup is greppable and a mandatory regression
test — is adapted from the `diagnose` skill (now `diagnosing-bugs`) in
**[mattpocock/skills](https://github.com/mattpocock/skills)** by
**[@mattpocock](https://github.com/mattpocock)**, licensed under
**[MIT](https://github.com/mattpocock/skills/blob/main/LICENSE)**.

The skill text here is original and considerably condensed; the loop's structure and
several of its specific disciplines are his.

A second review the same day folded in more of the upstream's thinking, 323 commits on
from the original borrow: the feedback loop as the *deliverable* of step 1 (with its
tighten-it pass and completion criteria), raising the *reproduction rate* rather than
chasing a clean repro on non-deterministic bugs, generating 3–5 ranked hypotheses instead
of one, one-variable-at-a-time probing, the measure-first branch for performance work,
secret redaction before showing output, the "correct seam" rule for regression tests —
including *"if no correct seam exists, that itself is the finding"* — and the post-mortem
step. Wording remains original throughout.

Not adopted, deliberately: the enumerated ten-way catalogue of loop constructions and the
human-in-the-loop script asset (too long and too tool-coupled for this playbook's
register), and the handoff to an architecture skill this playbook does not have.

**This credit was missing until 2026-08-15.** It was recorded correctly in the source
project when the skill was first written (AppliHawk commit `c307e69c`, 2026-06-11 —
*"Borrowed from mattpocock/skills 'diagnose' concept"*) and was lost when the skill was
distilled into this playbook. Noting it here rather than quietly backfilling: a playbook
that sells provenance as a system should show what its own system missed. See the
completeness sweep added to `/upstream-check` for the mechanism that would have caught it.

## skills/diagnose/ — step 4a — concept credit

The reorientation tripwire (step 4a, and the matching bullet in principle 4) takes the
*Orient* stage of the **OODA loop** — **John Boyd**'s decision cycle, developed in USAF
briefings and the 1976 essay *Destruction and Creation*. Boyd's diagram makes Orientation
the dominant node, feeding every other stage: your model filters what you are able to
observe, so repeated failure inside a loop indicts the model rather than the effort. The
step text is original; that insight is his.

Deliberately partial. The famous half of OODA — **tempo**, "getting inside the opponent's
decision loop" — assumes an adversary who is also orienting, and a bug is not reacting to
you. Boyd's **implicit guidance** fast path (Orient wiring straight to Act, skipping
Decide, when the situation is familiar) is the exact behaviour this skill exists to
suppress: an assistant's dominant failure mode is acting quickly on a stale model. Only
the Orient stage is imported.

Boyd died in 1997 and the source is a fixed text, so there is nothing to track for
updates and this source has no [UPSTREAMS.md](UPSTREAMS.md) row.

## skills/docs-lint/ — concept credit

The lint operation is inspired by the *lint* step of **Andrej Karpathy's**
[LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) pattern.
The skill text is original; the idea that knowledge bases need periodic
contradiction/staleness checks by the LLM that maintains them is his.

## rules/dependency-lockfile.md — "before a new dependency" section — concept credit

The agent-aware pre-install checkpoint (verify a package exists, isn't a
typosquat/hallucination, is not deprecated, and is CVE-clean before adding it) is
inspired by **[depshield-mcp](https://github.com/devanshkaria88/depshield-mcp)** by
**[@devanshkaria88](https://github.com/devanshkaria88)**. The rule text is original; the
insight — that AI agents install from stale memory with no gate between decision and
install — is theirs.

## skills/ format

The skill-file conventions echo Anthropic's Claude Code skill/plugin format so the
files double as plugin skills; the workflows themselves are original or attributed
above.
