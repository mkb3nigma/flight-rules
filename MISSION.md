# Mission

> What flight-rules is for, so that a change is judged against it and not only for
> being correct. This file is for the people and assistants who change flight-rules;
> `hooks/README.md` → *What these hooks are — and are not* is the adopter-facing
> statement of the guard half.

## What it is

flight-rules helps a competent developer — working alone or with AI assistants, which it
holds to the same standard — keep good code hygiene: the small things that are easy to
overlook — a check not run, a doc left describing the old behaviour, a claim of "done"
with nothing behind it, a worktree left behind — and four catastrophes: a leaked key, a
commit on a protected branch, a protected branch moved without review, work destroyed or
history rewritten, either on a protected branch. It is one source of truth, consumed by
many projects and any assistant that reads Markdown. That is the whole job.

It is not a security boundary (principle 1), and not a project's CI or its own checks:
those live in that project — its pipeline, its `.ai/` extensions (#65). What it finds
left behind that it did not make — a container testing started — it names, and does not
stop (#109).

## What it holds to

1. **Hygiene, not a security wall.** Anyone who means to get past it can, and it does
   not try to stop them. It assumes a developer who can take responsibility, and adds no
   block for a mistake a competent developer would not make.

2. **Evidence over assertion.** A claim is checked, not trusted — by a hook where one
   can, by the command, its exit status and its output where one cannot. A rule is here
   because a named failure, a pinned upstream or declared testimony says so, never
   because it is best practice; a pre-existing item with no warrant is given one, or
   declined by the owner at the release review (`CLAUDE.md` → *How a rule gets in*),
   and the decision recorded. What the hooks do *not* catch is measured and written down
   (`hooks/README.md`'s tables), not implied away. Adapted work is credited and pinned
   to the ref reviewed.

3. **Generic, and tool-agnostic.** Everything that ships would belong in any project
   that adopts it, with any assistant — a thin adapter for one tool included. A
   project's own flavour lives in that project's `.ai/` (README → Layout); this repo's
   own `CLAUDE.md` and conf are its extension. Logic in a shipped script that a tool's
   config merely wires is the playbook's; a capability that exists for one tool only is
   one-tool, and question 2 weighs it.

4. **Lightweight.** `engineering-principles.md` is injected into every session of every
   adopting project; the rest of `rules/` is read on the pointer; a skill loads its
   description always and its body when invoked; hooks cost context only when they
   speak, and maintenance always. A `rules/` line goes when its warrant is gone or
   another line covers it (`CLAUDE.md` → *How a rule gets in*, point 3); a refusal goes
   when what it costs outweighs what it catches (question 1).

5. **Stop and say.** Where it cannot go on, it stops, names what it saw and why that is
   refused, and prints the legitimate route where one exists that is not the skip itself
   — a route a person can take without an assistant, since the developer working alone
   is served as much as the one working with one. Where nothing needs doing, its hooks
   and checks say nothing: a notice that repeats on every healthy run is noise, and
   noise hides the warning that matters. flight-rules' own automation — the sync, the
   doctor — makes no branch, worktree or file write for the developer to get round a
   stop (#99). The assistant takes the printed route and no other — a skip is the
   person's decision — and pushes nothing unasked.

## The five questions

Every change answers question 3, with its lines added by class. Beyond that, a change
answers the questions that apply to it, and says in a phrase which do not and why:

- All five apply to a change that adds or widens a rule, a refusal, a check (a CI gate
  included) or its wiring, a skill step, or a line that reaches a session. Making a
  check stricter widens it.
- A change that weakens or removes one of those — or a test of one, a documented
  boundary, a claim an upstream pin supports — answers question 1 with what it cost or
  why its warrant no longer holds, and question 2 with what an adopter loses with it. It
  names what it drops, and where that is covered or why it need not be.
- Anything else — a test or doc that weakens nothing, a fix or refactor that changes
  none of the above, an attribution, a CHANGELOG entry, a version bump, this repo's own
  conf — names what it is.

The answers go where the change is reviewed: the PR body, or, for a branch merged
locally, the commit message of the change itself.

1. **What went wrong without it — and was that reached by accident?** A slip — the wrong
   terminal tab, a `cd` that failed, a habit — an assistant acting without the
   developer's decision, or a shape an assistant emits routinely (a subshell, a chain,
   `git -C`) is what this repo guards against. A failure reached only on purpose by the
   developer — a crafted command, a forged byte — is recorded as an issue with its
   disposition and no fix scheduled, and is **not a warrant** for a refusal or a check;
   a probe counts when the path it shows is one a slip could also take. For a `rules/`
   or `MISSION.md` line, or a skill step, the warrant `CLAUDE.md` → *How a rule gets in*
   names is the answer; the accident test is asked of a refusal or a check. A removal
   answers with what the refusal cost — false positives, turns, the route-around it
   taught — or why its warrant no longer holds.
2. **Would every adopting project want it, with any assistant?** Asked of what ships:
   this repo's own `CLAUDE.md`, `MISSION.md`, conf and CI do not, and answer it so. If
   the honest answer names one project, it belongs in that project's extension; one
   tool, it ships only as the thin adapter principle 3 allows. A change that ships also
   says, under its CHANGELOG entry's *Upgrading*, what an adopter already on the
   previous release must do, or that nothing is needed; and an update never silently
   undoes what an adopter set — a hook copy newer than its own, a conf value they chose:
   a change that must replace one says so there.
3. **What does it cost — every reader, and whoever maintains it?** Lines added and net,
   by class (the *Releasing* paragraph of `CLAUDE.md` names the classes), stated with
   the change — advisory, no check reads it — and summed at the release, where
   `pr-create` 2b reports them with the CHANGELOG entry beside the number. This makes
   the cost visible; nothing in flight-rules refuses a release for its size — the
   owner's decision, with the number in view, is the gate. Size is not the failure;
   what hides in it is: a large diff is read for these questions subsystem by
   subsystem, as `/dg` reads it for defects. `CLAUDE.md`'s test mandate decides how a
   gap is closed, not whether; the tests a closed gap needs are part of its cost.
4. **Does it stop and say, or act for the developer?** When it refuses: does the refusal
   name its cause and print the legitimate route, where one exists that is not the skip
   itself — one a person can take without an assistant? When nothing needs doing, is it
   quiet on every run? A new refusal on a plausible everyday command is the owner's call
   — name the commands it would block, then ask.
5. **Is it enforced — or honest that it is not?** A hook, a CI check, or a skill with
   the check number — for a ref movement, a git hook (*What follows*); "advisory" only
   with the reason it cannot be checked. A dormant rule with a real warrant stays:
   nothing is cut for being advisory or for not having fired lately.

## What follows

- Prefer checks whose misfire is a false positive, not a silent pass. Question 1 decides
  whether a check exists; once it does, a construct it sees but cannot read is refused,
  not waved through (`hooks/README.md` → *every uncertainty resolves toward deny*) —
  this is where principle 1 yields, and what it refuses wrongly is part of its cost
  under question 1. A check's own crash, timeout or missing tool fails loud,
  unconditionally (`engineering-principles.md` §2); where the fix adds a refusal on
  legitimate work, question 4 applies.
- A ref movement is the git hooks' to refuse; the agent guard is an early, specific
  message, not the enforcement (`hooks/README.md` → the layering lesson).
- Where the questions are asked: `pre-merge-check` item 18 asks a rules-file diff for
  its warrant and its enforcement; `/dg` asks every change in this repo the questions
  that apply to it (`.ai/skills/dg/EXTENSIONS.md`), and the whole release diff at
  `pr-create` 2b, subsystem by subsystem. No hook checks any of them, and questions 2, 3
  and 4 only `/dg` asks — advisory, and said so.

## How this file changes

By the owner's decision. No hook reads this file: `pre-merge-check` item 18 asks its
three asks — warrant, failure, enforcement — of what a diff adds to or widens in it, and
a cut names what it drops and where it is now covered; `/dg` reviews the diff with each
finding's disposition recorded where the change is reviewed; the owner merges. An
assistant does not edit the mission to admit a change: if a change cannot answer the
five questions, the change gives way — or the assistant reports the question it cannot
answer as a finding for the owner, who may change this file.
