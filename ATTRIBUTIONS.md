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
format; parameterized project-specific behavior into local-extension sections; the
dependency scan runs only tools already installed; the comic is drawn as text after the
header of every verdict rather than offered, governed per project by `DG_COMIC` and
`DG_COMIC_PR`, and the HTML page is made only on request.
`skills/dg/comic-template.html` is upstream's `dg/comic-template.html` at `48d2f642`,
with a Content-Security-Policy meta tag added (no script, form or
`<base>` in a page filled from the subject under review; a meta refresh still
navigates, so escaping stays the control), the FIXED tag renamed AGREED, and "Final
Score" renamed "Banter Score".

## rules/engineering-principles.md — principles 1–4

Adapted from **[andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills)**
by **multica-ai**, licensed under
**[MIT](https://github.com/multica-ai/andrej-karpathy-skills/blob/main/LICENSE)** —
itself derived from **Andrej Karpathy's** public observations on LLM coding pitfalls.

Modifications in this repo: restructured into the current seven-principle format,
reworded bullets, and merged or dropped the ones that restructuring made redundant.
Principle 5 does not come from this source — see below. Principles 6 and 7 are original
to this repo and need no credit.

## rules/engineering-principles.md — principle 5 — concept credit

Principle 5 ("Suggest Better Ways") is owed to **an unnamed Reddit post** — unnamed
because neither the author nor the link was recorded at the time, not because the
author posted anonymously. The observation was that an assistant staying quiet about a
better approach is itself a failure mode. The wording here is original; the insight is
theirs. If the post resurfaces, credit the author and add the permalink here. There is
nothing to track for updates, so this source has no [UPSTREAMS.md](UPSTREAMS.md) row.

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

A third review (2026-11-12, `8b78b531` to `4ae2317d`, 128 commits) folded in one check,
from upstream commit `f3fc5632` (#1209, 2026-10-07): the regression test is watched
failing before the fix, and a red forced by breaking code or a fixture is trusted only
once a diff against a clean copy shows the break landed (step 6). Wording original.
Not adopted, deliberately: upstream dropped the post-mortem question ("what would have
prevented this bug?") into a separate `retro` skill; this playbook has none, so step 8
keeps it.

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

## skills/ format

The skill-file conventions echo Anthropic's Claude Code skill/plugin format so the
files double as plugin skills; the workflows themselves are original or attributed
above.

## skills/ux/ — interface guidance

`accessibility.md` and part of `forms.md` follow the **[Web Content Accessibility
Guidelines (WCAG) 2.2](https://www.w3.org/TR/WCAG22/)** (W3C Recommendation, 12 December
2024), level AA, citing each success criterion by number; the wording is this skill's
own summary, not the specification's text, and the thresholds were read from it. The
practice they add beyond a criterion, and the markup they ask for, rest on W3C's
supporting documents: the **[WAI-ARIA Authoring Practices](https://www.w3.org/WAI/ARIA/apg/)**
(the modal dialog pattern, the keyboard interface, *Read Me First*, the sortable table),
the **[WAI Tables Tutorial](https://www.w3.org/WAI/tutorials/tables/)**, *Understanding
WCAG 2.2* for 1.3.2, 1.3.3, 1.4.13, 2.1.4, 2.4.2 and 2.5.2, techniques ARIA21 and G212,
failures F54 and F101, and ACT rule b4f0c3; and on MDN's pages on the `dialog` element,
the `hover` media feature and `aria-disabled`. `forms.md` also follows the **[GOV.UK
Design System](https://design-system.service.gov.uk/)** (the error summary and the
validation pattern, recording where it disputes a rule), the **[HTML
Standard](https://html.spec.whatwg.org/)**'s form submission algorithm, and GDPR
recital 32 on consent. Each is summarised in this skill's own words and named beside
its rule.

`principles.md`, `states.md` and `forms.md` restate published findings in their own
words, each named with its source: Hick (1952) and Hyman (1953); Fitts (1954); the
isolation effect (von Restorff 1933); the Gestalt principles, with common region (Palmer 1992) and
uniform connectedness (Palmer and Rock 1994); working-memory capacity (Cowan 2001,
revising Miller 1956); the serial position effect; the aesthetic-usability effect
(Kurosu and Kashimura 1995); the peak-end rule (Kahneman); the goal-gradient effect
(Kivetz, Urminsky and Zheng 2006); the Zeigarnik and Ovsiankina effects as weighed by
Ghibellini and Meier (2025); response-time limits as given by Nielsen Norman Group;
the Core Web Vitals responsiveness threshold and the layout-shift guidance (web.dev);
Jakob's law, the second of the ten usability heuristics and *User Control and Freedom*
(Nielsen and Nielsen Norman Group); Baymard Institute's benchmark of Back button
expectations; Tesler's law; Postel's robustness principle (RFC 761).

The starting list was **[The UX laws in my CLAUDE.md](https://adamhayes.xyz/blog/the-ux-laws-in-my-claude-md)**
by Adam Hayes (2026-09-01), which states no licence; no text is taken from it. What
changed in the taking: accessibility, states and forms added; each rule labelled as a
standard, a finding or a rule of thumb, with its limit; Miller's seven replaced by
Cowan's three to five; the 0.4 s response figure replaced by the 0.1 / 1 / 10 s limits
and the web's 200 ms threshold; the Zeigarnik effect kept only as resumption;
Parkinson's law and Occam's razor left out as not interface findings.

The structure of `audit.md`, the scored audit of an existing interface, is adapted from
**[Impeccable](https://github.com/pbakaus/impeccable)** (`pbakaus/impeccable`, Apache 2.0),
`skill/reference/audit.md` and `skill/reference/critique.md` read at `b4bff162`; the
idea only, no text taken. Taken: an audit documents and does not fix; one score per
area beside the findings, with the key finding's ID; a section for patterns, one
problem recurring across the interface; n/a for an area that does not apply; and an
area that could not be judged is not scored rather than passed. Not taken: its judged score levels (here a score is worked out from the
findings register and can be recomputed), its totals and rating bands, its P0–P3
severities (this guide rates Major, Medium and Minor by effect), the open-critique
parts (gut reaction, personas, questions to consider, praise), its performance, theming
and integrity areas, which have no rules here yet, and its saved-report scripts.
