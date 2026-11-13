# Auditing an existing interface

Read this file when the task is to review an interface that already exists, not to build
one. It is not a topic: it holds no rules of its own, and says how to hold an interface
to the topics' rules and score the result.

## What an audit is

An audit records findings and scores. It changes nothing unless the person asks, and it
does not redesign: a finding names the rule, where it fails and the fix, and the fixing
is a separate task.

## The walk

1. Read `{DESIGN_RECORD}`, and every topic file in `SKILL.md`'s table — all four, not
   only the ones a build would need.
2. Name the main task: the thing most people come to the interface to do.
3. Walk the main task first, then one screen or flow at a time. For each, use Build
   mode step 5's evidence and passes; a rule the evidence could not show is **not
   checked**, never passed.
4. Name every screen and flow looked at. Any other is **not checked**, and the report
   says so.

**No design record yet.** Write one from what is there — tokens, components, patterns —
and record where the interface already disagrees with itself: two button styles for the
same job, three greys for one kind of text. Each disagreement is a finding against the
record (`Rule`: "record"), left for the person to settle, not settled by choosing one.
The report says the record was written by this audit.

## The score — worked out, never judged

One score per area, from that area's findings in the register: **accessibility**,
**states**, **forms**, **principles** (the topics' `UX-A`, `UX-S`, `UX-F` and `UX-P`
rules) and the **design record** (the "record" findings). Take the worst Rating among
the area's findings, and whether a finding at that Rating is on the main task:

| Score | The area's findings |
|---|---|
| 5 | none |
| 4 | Minor only |
| 3 | the worst is Medium, and no Medium finding is on the main task |
| 2 | the worst is Medium, and a Medium finding is on the main task |
| 1 | the worst is Major, and no Major finding is on the main task |
| 0 | a Major finding is on the main task |

Beside each score, its counts: Major, Medium, Minor, and the area's rules **not
checked**. An area whose topic does not apply — no form anywhere — is **n/a**. An area
with more than half of its rules **not checked** is **not scored**: it gets no number
it was not checked for. A score is never adjusted by feel; anyone holding the register
can recompute every score, and the report says so.

There is **no total** across areas. The areas are not interchangeable: accessibility
comes first (`SKILL.md`, *When rules pull against each other*), and a sum would let a
good forms score hide a failing accessibility one.

## The report

As `SKILL.md`'s Report, in this order:

1. **The score table** — area, score, Major / Medium / Minor, not checked, and the ID
   of the finding that set the score.
2. **The findings register**, worst first, in `SKILL.md`'s columns unchanged.
3. **Patterns.** One rule failing in many places is one finding, with its count and
   two or three examples, not one finding per place: a missing focus ring on every
   button is one fix, and counting it forty times would bury the rest.
4. **Not checked**, and why: the screens and flows not walked, the rules the evidence
   could not show, the passes that could not run.
5. **The fixes, in order**: Major first; within each Rating, the smallest fix first.
6. **The design record**: written by this audit, or the changes it needs.

## Auditing again

A later audit compares its scores with an earlier one only over the same screens and
flows, walked the same way. A different walk is a new baseline, not a comparison: say
which screens changed between the two.
