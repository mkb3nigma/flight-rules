# Auditing an existing interface

Read this file when the task is to review an interface that already exists, not to build
one. It is not a topic: it holds no rules of its own, and says how to hold an interface
to the topics' rules and score the result.

## What an audit is

An audit records findings and scores. It changes nothing unless the person asks, and it
does not redesign: a finding names the rule, where it fails and the fix, and the fixing
is a separate task.

## The walk

1. Read `{DESIGN_RECORD}`, and every topic file in `SKILL.md`'s table.
2. Name the main task: what most people come to the interface to do.
3. Walk every screen and step of the main task first, then one other screen or flow at
   a time. For each, use Build mode step 5's evidence and passes.
4. Name every screen and flow walked, marking those that belong to the main task. Any
   other is **not checked**.

**No design record yet.** Draft one in the report from what is there — the tokens,
components and patterns seen — and list where the interface disagrees with itself (two
button styles for one job, three greys for one kind of text) as open decisions for the
person to settle. Offer to save the draft as `{DESIGN_RECORD}`; write no file unless
asked, as Build mode step 1 does.

## Findings and outcomes

A finding is **on the main task** if it occurs on any screen or step of the main-task
walk, page-wide ones included (the header, the skip link, the page language); a pattern
is, if any of its instances is. `Where` says so: "main task: checkout / card form".

An inconsistency is filed against an existing record as "record". Where there was no
record before the audit, it is filed under UX-P07 instead, and the design record area is
**not scored**: there was nothing yet to compare against.

One defect is filed once, under the most specific rule that covers it: a field's
missing label is UX-F01, not also UX-A18; a colour-only error is UX-F14, not also
UX-A10. Where the design record itself breaks a rule — a colour pair in it fails
contrast — the finding goes under that rule and its area (UX-A08), with `Where` naming
the record, not under "record".

Each rule of every topic has one outcome over the walked screens:

| Outcome | When |
|---|---|
| finding | it fails somewhere walked: a row in the register |
| no finding | the evidence showed it, and it holds |
| does not apply | nothing it governs is present: no drag, no time limit, nothing flashes |
| not checked | no walked screen gave evidence for it |

## The score — worked out, never judged

One score per area, from that area's findings in the register: **accessibility** (the
`UX-A` rules), **states** (`UX-S`), **forms** (`UX-F`, the WCAG criteria in `forms.md`
included), **principles** (`UX-P`) and the **design record** (the "record" findings).
Take the worst Rating among the area's findings, and whether a finding at that Rating
is on the main task:

| Score | The area's findings |
|---|---|
| 5 | none |
| 4 | Minor only |
| 3 | the worst is Medium, and no Medium finding is on the main task |
| 2 | the worst is Medium, and a Medium finding is on the main task |
| 1 | the worst is Major, and no Major finding is on the main task |
| 0 | a Major finding is on the main task |

Beside each score, its counts: Major, Medium, Minor, and the area's rules **not
checked** (for the design record, which has no rules, "—"). A rule that does not apply
leaves the count. An area whose rules all do not apply — forms, with no input and no
destructive action on any walked screen — is **n/a**. An area with more than half of
its remaining rules **not checked** is **not scored**: it gets no number it was not
checked for.

With `SKILL.md`'s floor, a failed criterion on the main task holds accessibility (or
forms) at 2 or below, however small the fix; the counts beside the score carry the
detail.

A score is never adjusted by feel. Anyone holding the register, the named main task with
its screens, and the lists of rules not checked and not applying can recompute every
score, and the report says so.

There is **no total** across areas. The areas are not interchangeable: accessibility
comes first (`SKILL.md`, *When rules pull against each other*), and a sum would let a
good forms score hide a failing accessibility one.

## The report

`SKILL.md`'s Report, in this order:

1. **The walk** — the main task, and every screen and flow walked, the main task's
   marked.
2. **The score table** — area, score, Major / Medium / Minor, not checked, and the ID of
   the key finding, the one that set the score: on a tie, the first in register order
   among the worst-rated, those on the main task first.
3. **The findings register**, worst first, in `SKILL.md`'s columns unchanged. One problem
   recurring in many places is one finding, with its count and two or three examples,
   not one finding per place: a missing focus ring on every button is one fix, and
   counting it forty times would bury the rest. Two different problems under one rule
   are two findings.
4. **Not checked**, and why — the rules not checked and the rules that do not apply,
   by area; each rule evidenced on only some of the walked screens where it applied,
   with the screens missed (the scores do not change); the passes that could not run —
   and, for each rule the eye cannot judge, the evidence, as `SKILL.md`'s Report asks.
5. **Any rule traded** for another, and why.
6. **The fixes, in order**: Major first; within each Rating, the smallest fix first.
7. **The design record**: the draft, or the changes the existing one needs.
8. **The by-eye script** from `SKILL.md`'s Report, the steps that apply.

## Auditing again

A later audit compares its scores with an earlier one only over the same screens and
flows, walked the same way. A different walk is a new baseline, not a comparison: say
which screens changed between the two.
