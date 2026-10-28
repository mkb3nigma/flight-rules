# Mission

> What flight-rules is for, so that a change is judged against it and not only for
> being correct. This file is for the people and assistants who change flight-rules;
> the adopter-facing long form of the guard half is `hooks/README.md` → *What these
> hooks are — and are not*.

## What it is

flight-rules helps a competent developer, and the AI assistants working with them, keep
good code hygiene: the small things that are easy to overlook — a check not run, a doc
left describing the old behaviour, a claim of "done" with nothing behind it, a worktree
left behind — and four catastrophes: a leaked key, a commit on a protected branch, a
protected branch moved without review, work destroyed or history rewritten on a
protected branch. It is one source of truth, consumed by many projects and any
assistant that reads Markdown. That is the whole job.

## What it holds to

1. **Hygiene, not a security wall.** Anyone who means to get past it can, and it does
   not try to stop them. It is not a babysitter: it assumes a developer who can take
   responsibility, and it adds no block for a mistake a competent developer would not
   make.

2. **Evidence over assertion.** A claim is checked, not trusted — by a hook where one
   can, by the command, its exit status and its output in the report where one cannot.
   A rule is here because a named failure, a pinned upstream or declared testimony says
   so (`CLAUDE.md` → *How a rule gets in*, point 1) — never because it is best practice.
   A pre-existing item with no warrant is given one, or declined by the owner at the next
   release, and the decision recorded. What the hooks do *not* catch is measured and
   written down, not implied away. Adapted work is credited and pinned to the ref
   reviewed.

3. **Generic, and tool-agnostic.** Everything that ships — `rules/`, `skills/`,
   `hooks/`, the READMEs — would belong in any project that adopts it, with any
   assistant. A project's own flavour — its test commands, its baselines, its extra
   checks — lives in that project's `.ai/`: its `master-rules.md`, `.ai/rules/`,
   per-skill `EXTENSIONS.md` and `flight-rules.conf`; this repo's own `CLAUDE.md` and
   conf are its extension. Plain Markdown and plain git carry the rules; a tool's own
   config is a thin adapter — a manifest, a hook wiring — around logic kept outside it,
   never the home of the logic.

4. **Lightweight.** `rules/` loads into every session of every adopting project through
   its pointer file; a skill loads its description always and its body when invoked;
   hooks cost context only when they speak — a refusal, a warning, a cleanup list — and
   each line of that is priced too. What hooks cost instead is maintenance: every line
   of hook, test and CI is re-run and re-read at every change. A line that costs every
   reader and helps none goes, however true it is.

5. **Stop and say; never route around a stop for the developer.** Where it cannot go
   on, it stops, names what it saw and why that is refused, and prints the legitimate
   route where one exists that is not the skip itself — a route is for the person to
   run, reported by the assistant. It makes no branch, worktree, push or file write to
   get round a stop (#99). A block that withholds a route that exists teaches the next
   assistant to route around blocks.

## The five questions

A change that adds or widens a rule, a refusal, a check, a skill step, or a line that
reaches a session answers all five. Any other change names its class — test,
attribution, CHANGELOG, release, CI — and the class is the reason; one that fits no
class answers all five. The answers go where the change is reviewed: the PR body, or,
for a branch merged locally, the `pre-merge-check` report and the merge commit.

1. **What went wrong without it — and was that reached by accident?** A slip — the
   wrong terminal tab, a `cd` that failed, a habit — or an assistant acting without the
   developer's decision is what this repo guards against. A failure that needs a crafted
   command, a case-variant ref name or a forged byte is reached only on purpose: it is
   recorded as an issue with its disposition and no fix scheduled (#106 is the model),
   and it is **not a warrant** for a rule, a refusal or a check. A probe counts when the
   path it shows is one a slip could also take; #106's is not. A removal answers this
   question with what the refusal cost — false positives, turns, the route-around it
   taught.
2. **Would every adopting project want it, with any assistant?** Asked of what ships.
   If the honest answer names one project, it belongs in that project's extension. If
   it names one tool, it ships only as the thin adapter point 3 allows, logic kept
   outside it.
3. **What does it cost — every reader, and whoever maintains it?** Words before and
   after for each file that reaches a session, and lines added to `hooks/`, tests and
   CI. The count is the check, reported at the release (`pr-create` 2b). Whether it is
   proportionate to the slip it closes is the owner's call, made with question 1's event
   beside the number — advisory, because the repo records events, not how often a slip
   occurs.
4. **Does it stop and say, or act for the developer?** When it refuses: does the
   refusal name its cause and print the legitimate route, where one exists that is not
   the skip itself? A new refusal on a plausible everyday command is the owner's call —
   name the commands it would block, then ask.
5. **Is it enforced — or honest that it is not?** A hook, or a skill with the check
   number; "advisory" only with the reason it cannot be checked. A dormant rule with a
   real warrant stays: nothing is cut for being advisory or for not having fired lately.

## What follows

- Prefer checks whose misfire is a false positive, not a silent pass. Question 1 decides
  whether a check exists; once it does, a construct it cannot read is refused, not waved
  through (`hooks/README.md` → *every uncertainty resolves toward deny*) — the cost is a
  false positive, which question 4 prices. A check's own crash, timeout or missing tool
  fails loud (`engineering-principles.md` §2); fixing such a fail-open is welcome when
  it adds no new refusal on legitimate work.
- A finding that asks for a new refusal is weighed by question 1 like any other
  proposal; one that asks for a loosening, by what the refusal costs. Declining either
  needs its reason, as applying it does.
- `CLAUDE.md` → *How a rule gets in* is the procedure that applies these questions to
  `rules/`; this file is the reason behind the procedure.

## How this file changes

By the owner's decision. No hook reads this file: `pre-merge-check` item 18 asks its
three questions of a diff that touches it, `/dg` reviews the diff with the verdict and
each finding's disposition recorded where the change is reviewed, and the owner merges
— beyond that, advisory. An assistant does not edit the mission to admit a change: if a
change cannot answer the five questions, the change gives way — or the assistant reports
the question it cannot answer as a finding for the owner, who may change this file.
