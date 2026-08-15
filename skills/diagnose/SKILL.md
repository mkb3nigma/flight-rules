---
name: diagnose
description: Structured debugging loop for hard bugs and performance regressions — build a feedback loop, minimize, hypothesize, instrument, reorient when stuck, fix, verify, clean up. No fix without a reproduction.
---

# /diagnose — Structured Debugging Loop

## Project extensions

Before executing, check the consuming project for `.ai/skills/diagnose/EXTENSIONS.md`.
If present, read it first: it supplies the project's `{PLACEHOLDER}` values, plus any
additional or replacement steps and project-specific rules — extensions take
precedence over the generic defaults below. If absent, use the defaults as-is.

Debug a reported bug methodically: reproduce → minimize → hypothesize → instrument →
(reorient) → fix → verify → clean up → post-mortem. Never jump straight to a fix.

## Invocation

```
/diagnose <bug description, error message, stack trace, or issue link>
```

If empty, ask for: what was observed, what was expected, and any error output or steps.

## Purpose

Bug reports arrive vague ("the button does nothing", "I got a 500"). The temptation is
to pattern-match to a cause and patch it. This loop prevents wrong fixes: **you may not
write a fix until you have a reproduction and a confirmed hypothesis.**

Three gates carry most of the weight, and each blocks a distinct failure: step 1 (no
loop, no diagnosis), step 3 (multiple ranked candidates, so you don't anchor on the
first), and step 4a (three deaths means the frame is wrong, not the effort).

## Process

### 1. Reproduce — build a feedback loop
**This step is the skill; the rest is mechanical.** The deliverable is not "I saw the
bug once" but a *loop*: one command you can run on demand that goes red on this bug.
Given one, bisection and hypothesis-testing just consume it. Without one, no amount of
reading code will save you — so spend disproportionate effort here.

Reach for the tightest seam that reaches the bug: a failing automated test, else a
script/curl against a running service, a CLI invocation diffed against known-good
output, a headless browser script, a replayed capture, or a throwaway harness that
calls the failing path directly. Record the exact trigger: inputs, state, environment.

Then **tighten it** — treat the loop as a product. Faster (cache setup, narrow scope),
sharper (assert the specific symptom, not "didn't crash"), more deterministic (pin time,
seed RNG, freeze network). A 30-second flaky loop is barely better than none; a
two-second deterministic one is a different job.

Done when you can name **one command you have already run**, whose output you can show,
and which is: red-capable on *this* symptom, deterministic, fast, and runnable
unattended.

**Non-deterministic bugs:** the goal is not a clean repro but a *higher reproduction
rate*. Loop the trigger, parallelise, add stress, inject sleeps to widen the window. A
50%-flake is debuggable; a 1% flake is not — raise the rate until it is.

**Do not fix a bug you cannot reproduce.** If genuinely irreproducible, say so
explicitly, list what you tried and ruled out, and name what would unblock it (access
to the environment, a captured artifact, permission to instrument production) — then
stop. Do not proceed to hypothesise without a loop.

**Redact before showing.** This loop produces raw output — logs, headers, payloads.
Replace every secret with `<REDACTED>` before putting it in front of anyone, and drive
loops from env vars so credentials stay out of what you display.

### 2. Minimize
Shrink the reproduction to the smallest trigger that still goes red. Strip inputs field
by field; drop steps one by one; re-run the loop after each cut. Find the boundary that
flips working↔broken. If a recent change is suspected, bisect (`git bisect run
<repro-script>` when scriptable).

Done when **every remaining element is load-bearing** — removing any one of them makes
the loop go green. A minimal repro shrinks the hypothesis space in step 3 and becomes
the regression test in step 6.

### 3. Hypothesize
Write down **3–5 ranked candidates before testing any of them**. Generating one at a
time anchors you to the first plausible idea — and an anchored search is one that
investigates a single branch thoroughly while never looking at the others.

(This is the *preventive* half. Step 4a is the reactive half, for when the candidates
were diverse and still all wrong — that indicts the frame they were drawn from, which
generating more candidates cannot fix.)

Each must be falsifiable — state the prediction: *"If X is the cause, then changing Y
makes the bug vanish / Z will show W."* No stateable prediction means it is a vibe, not
a hypothesis; sharpen it or drop it. Then test the cheapest-to-check first, and name the
observation that would disprove it.

Show the ranked list to the user before testing. They routinely re-rank it in one line
("we deployed a change to #3 yesterday") or have already ruled one out. Don't block on
a reply — proceed with your own ranking if they're away.

### 4. Instrument
Confirm or kill the hypothesis with targeted instrumentation — don't guess from reading
code alone. **Each probe must test a specific prediction from step 3, and you change one
variable at a time.** Prefer a debugger or REPL where the environment allows one — a
single breakpoint beats ten log lines — then targeted logs at the boundary that
distinguishes the candidates. Never "log everything and grep".

Tag every temporary line with `# DIAG` / `// DIAG` so cleanup is greppable. Disproved →
back to step 3 with what you learned. Loop until confirmed — but **count the disproved
hypotheses**, and at three go to 4a before testing a fourth.

**Performance regressions take the other branch:** logs are usually the wrong tool.
Establish a baseline measurement first (timing harness, profiler, query plan), then
bisect against it. Measure first, fix second.

### 4a. Reorient — mandatory after three disproved hypotheses
Three failures is not a prompt for a fourth hypothesis. It is evidence that the frame is
wrong — and the candidates still left on your step-3 list were drawn from that same
frame, so they inherit the same blind spot. Stop working the list and attack what all
three shared:

- **Is the reproduction reproducing the reported bug** — or a different one that happens
  to look the same?
- **Are you looking at the code that runs?** Right service, process, branch, container,
  build, cache. A stale artifact has eaten many afternoons.
- **Is a tool lying to you?** A mock that no longer matches reality, a swallowed
  exception, a log level that drops the line you need, a harness that stubs the very
  thing under test.
- **Is the layer right?** If every hypothesis has been in application code, question what
  you have been treating as trustworthy: framework, driver, clock, filesystem, network.
- **What have you assumed since step 1 without ever checking?** Write the assumptions
  down and verify one — cheapest first.

Then restate step 3 from the new frame. Report what reorientation changed; "nothing"
is a valid answer and is itself a finding worth recording.

> Named for the *Orient* step of Boyd's OODA loop — the stage his diagram makes dominant
> and popular retellings reduce to a waypoint. His claim is that orientation filters what
> you are able to observe, so a wrong model does not merely slow the loop down: it makes
> the loop's own output appear to confirm it.

### 5. Fix
Only now write the fix — for the cause the instrumentation confirmed, not a symptom
upstream or downstream of it. Keep it surgical (see engineering principles §3).

### 6. Verify
The step-1 loop no longer goes red — re-run it against the *original*, un-minimized
scenario, not just the minimized one. The full relevant suite still passes. The failing
repro is committed as a permanent regression test.

**Write the regression test at a correct seam, or say there isn't one.** A correct seam
exercises the real bug pattern as it occurs at the call site. A unit test that cannot
replicate the chain which triggered the bug, or a single-caller test for a bug that needs
several, gives false confidence — worse than no test, because it looks like coverage. If
no correct seam exists, **that is itself a finding**: report it, because the architecture
is what is preventing the bug from being locked down.

### 7. Clean up
`grep -rn "DIAG"` — remove every instrumentation line you added; delete throwaway
harnesses or move them somewhere clearly marked. The diff should contain the fix and the
regression test, nothing else.

### 8. Post-mortem
Two sentences, not a document:

- **Record the hypothesis that turned out correct** in the commit or PR message. The next
  person to touch this code inherits the reasoning, not just the patch.
- **Ask what would have prevented this bug.** If the answer is structural — no good test
  seam, tangled callers, hidden coupling — say so as a recommendation, *after* the fix is
  in. You know more now than when you started, and a fix that teaches nothing is half a
  fix.

## Output

Report: the feedback-loop command (redacted), minimized trigger, confirmed cause with the
evidence, the fix, and verification results. If a reorientation happened, say what frame
you abandoned and what replaced it — that is the reusable lesson, more than the fix is.
If no correct test seam existed, say so and name what would be needed. If any step was
skipped, say which and why.
