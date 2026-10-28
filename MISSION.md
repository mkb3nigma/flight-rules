# Mission

> What flight-rules is for, so that a change is judged against it and not only for
> being correct. Read first in this repo; every change answers the five questions
> below. The long form of the guard half, for adopters, is `hooks/README.md` → *What
> these hooks are — and are not*; this file is for the people and assistants who
> change flight-rules.

## What it is

flight-rules helps a competent developer, and the AI assistants working with them, keep
good code hygiene: the small things that are easy to overlook — a check not run, a doc
left describing the old behaviour, a claim of "done" with nothing behind it, a worktree
left behind — and three catastrophes: a leaked key, a commit on a protected branch, a
protected branch moved without review. It is one source of truth, consumed by many
projects and any assistant that reads Markdown. That is the whole job.

## What it holds to

1. **Hygiene, not guardrails.** It is not a security wall: anyone who means to get past
   it can, and it does not try to stop them. It is not a babysitter: it assumes a
   developer who can take responsibility, and it blocks no common command "for safety".

2. **Evidence over assertion.** A claim is checked, not trusted — by a hook where one
   can, by the command, its exit status and its output in the report where one cannot.
   A rule is here because something went wrong without it, named and dated; never
   because it is best practice. What the hooks do *not* catch is measured and written
   down, not implied away. Adapted work is credited and pinned to the ref reviewed.

3. **Generic, and tool-agnostic.** Everything here would belong in any project that
   adopts it, with any assistant. A project's own flavour — its test commands, its
   baselines, its extra checks — lives in that project's `EXTENSIONS.md` and
   `.ai/flight-rules.conf`, never in the playbook. Plain Markdown and plain git carry
   the rules; a tool's own config is a thin pointer, never the home of logic.

4. **Lightweight.** `rules/` and `skills/` load into every session of every adopting
   project; hooks cost no context. A line that costs every reader and helps none goes,
   however true it is.

5. **Stop and say; never act for the developer.** Where it cannot go on, it stops,
   names what it saw and why that is refused, and prints the command for what the
   person probably meant. It makes no branch, worktree, push or file write to get round
   a stop (#99). A block with no route teaches the next assistant to route around
   blocks.

## The five questions every change answers

1. **What went wrong without it — and was that reached by accident?** A slip — the
   wrong terminal tab, a `cd` that failed, a habit — is what this repo guards against.
   A failure that needs a crafted command, a case-variant ref name or a forged byte is
   reached only on purpose: it is recorded as an issue with "no fix" (#106 is the
   model), and it is **not a warrant** for a rule, a refusal or a check.
2. **Would every adopting project want it, with any assistant?** If the honest answer
   names one project or one tool, it belongs in that project's extension, not here.
3. **What does it cost every reader?** Words before and after, for each file that loads
   into a session. The cost is paid in every project, on every session, for as long as
   the line stays.
4. **Does it stop and say, or act for the developer?** And when it refuses: does the
   refusal name its cause and print the legitimate route? A new refusal on a plausible
   everyday command is the owner's call — name the commands it would block, then ask.
5. **Is it enforced — or honest that it is not?** A hook, or a skill with the check
   number; "advisory" only with the reason it cannot be checked. A dormant rule with a
   real warrant stays: nothing is cut for being advisory or for not having fired lately.

## What follows

- Prefer high-confidence checks. A speculative one fails open; a check whose own failure
  would read as "allowed" fails loud. Fixing a fail-open is welcome when it adds no new
  refusal on legitimate work.
- Reviewers push toward denies — that is what they are for. A finding is weighed by
  question 1, not by who raised it or how confident the report sounds.
- `CLAUDE.md` → *How a rule gets in* is the procedure that applies these questions to
  `rules/`; this file is the reason behind the procedure.

## How this file changes

By the owner's decision only, and reviewed as a `rules/` change: `/dg` on the diff, the
verdict and dispositions in the PR. An assistant does not edit the mission to admit a
change; if a change cannot answer the five questions, the change is what gives way.
