---
name: ux
description: Interface guidance for building or changing anything a person sees or operates — accessibility, states, forms and the basic UX principles, plus the project's own design record. Loads only the topics the task needs.
argument-hint: "[what is being built or changed]"
---

# /ux — Interface Guidance

## Project extensions

Read `.ai/skills/ux/EXTENSIONS.md` first if the project has one: its design system, an
accessibility target stricter than the default, the components to reuse, and
`{PLACEHOLDER}` values. It overrides the defaults below.

- `{DESIGN_RECORD}` — the project's design record (default `.ai/design.md`).

## What this is

The assistant designs and builds the interface; the person checks the result by eye.
This guide is the standard the work is held to, so that the design is sound and the
experience stays in good shape as the product grows. Visual taste — typography, colour,
a look that is not generic — is the project's, or a design skill's; this guide covers
whether the interface works.

## The topics

Load the ones the task needs, and only those. Each rule has an ID (`UX-A01`: the guide,
the topic's letter, a number), a kind — `[standard]` (a published standard),
`[finding]` (measured research), `[rule of thumb]` (practice, not measurement) — and,
where it has one, its source.

| Read | When the work |
|---|---|
| `accessibility.md` beside this file | puts anything on a screen. Always, for interface work. |
| `states.md` beside this file | loads, saves, submits or waits on anything; shows a list or data that can be empty. |
| `forms.md` beside this file | takes input: a form, a field, a search box, a settings page, a destructive action. |
| `principles.md` beside this file | lays out a screen, a menu or a flow; adds choices; decides what is primary. |

`sources.md` beside this file lists every source and the rules that rest on it. It is
for maintaining this guide, not for building: do not load it for a task.

## Build mode

1. Read `{DESIGN_RECORD}`. If there is none and the project already has an interface,
   say so and offer to write one from what exists; do not invent one silently.
2. Read the topics the task needs, from the table above.
3. Reuse a component or pattern the record names before making a new one.
4. Build.
5. Review the result against the loaded topics and the record. A rule is checked only by
   evidence that can show it: a screenshot for layout and colour; operating the
   interface for keyboard, focus and states; the markup or the accessibility tree for
   names, roles and announcements. Where the project runs, make these passes, each
   reported done or **not checked**: Tab through the main task with the mouse untouched,
   focus visible throughout; the page 320 px wide; text zoomed to 200%; each state of
   UX-S01 forced — no data, slow, failed; the longest plausible content (UX-S01);
   reduced motion on. Where only the code was read, list what could not be judged from
   it — contrast, focus order, timing, layout — as **not checked**. Never pass a rule
   silently.
6. Report (below).
7. If a token, component or pattern was added or changed, update the record in the same
   change — or start it, where this is the project's first interface — and say so.

To review an interface that already exists, run steps 1, 2, 5 and 6, and change nothing
unless asked.

## When rules pull against each other

Accessibility first. Then the person not losing work or making a mistake they cannot
undo. Then consistency with the design record. Then clarity over brevity. Name in the
report any rule knowingly traded for another, and why.

A design record that itself breaks a rule — a colour pair that fails contrast — is a
finding against the record, not something to copy.

## The design record

A Markdown file in the project, under four headings:

- **Tokens** — colours, type scale, spacing, radii: names and values.
- **Components** — each one, and when it is used instead of another.
- **Patterns** — how an error is shown, a form laid out, a destructive action
  confirmed, an empty or loading state drawn.
- **Decisions** — one dated line each, with the reason.

The consistency check reads it: a value not in **Tokens**, a second way of doing what
**Patterns** already does one way, a component rebuilt instead of reused — each is a
finding that names what should have been used.

## Report

As `engineering-principles.md` §7 asks. Findings in a register:

| ID | Where | Rule | Finding | Fix | Rating |
|---|---|---|---|---|---|

`Where` is a file and line, or a screen and element; `Rule` is the rule's ID, as
`UX-F01`, or "record" for a consistency finding. **Rating**, by effect: Major — it stops
a person, or loses their work or money; Medium — it slows or misleads them; Minor —
polish. A failed `[standard]` rule is never rated below Medium, and its finding names it
a conformance failure, with the WCAG criterion number.

For each rule the eye cannot judge — contrast, accessible names, roles and states,
status announcements, a label or error tied to its field, `autocomplete`, the page's
language and title — the evidence: the markup line, the accessibility tree, a measured
contrast ratio, the Tab order as walked; or **not checked**.

Then: what was **not checked**, any rule traded for another, the record changes, and a
short script the person can follow by eye, with no design knowledge: Tab through from
the top and watch the focus ring; narrow the window to phone width; zoom to 200%; submit
the form empty; turn the network off and retry — the steps that apply.

## What this is not

A design system, a brand, or a taste in fonts: those are the project's, in its record.
Nothing here is checked by a hook. Whether a screen has one clear purpose is a
judgement; this guide's review is where it is made, and the person's eye is where it is
confirmed.
