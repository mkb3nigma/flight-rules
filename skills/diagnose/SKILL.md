---
name: diagnose
description: Structured debugging loop — reproduce, minimize, hypothesize, instrument, reorient when stuck, fix, verify, clean up. No fix without a reproduction.
---

# /diagnose — Structured Debugging Loop

## Project extensions

Before executing, check the consuming project for `.ai/skills/diagnose/EXTENSIONS.md`.
If present, read it first: it supplies the project's `{PLACEHOLDER}` values, plus any
additional or replacement steps and project-specific rules — extensions take
precedence over the generic defaults below. If absent, use the defaults as-is.

Debug a reported bug methodically: reproduce → minimize → hypothesize → instrument →
(reorient) → fix → verify → clean up. Never jump straight to a fix.

## Invocation

```
/diagnose <bug description, error message, stack trace, or issue link>
```

If empty, ask for: what was observed, what was expected, and any error output or steps.

## Purpose

Bug reports arrive vague ("the button does nothing", "I got a 500"). The temptation is
to pattern-match to a cause and patch it. This loop prevents wrong fixes: **you may not
write a fix until you have a reproduction and a confirmed hypothesis.**

## Process

### 1. Reproduce
Get the bug to happen on demand before anything else. Prefer capturing it as a failing
automated test; otherwise a minimal script/curl/UI sequence. Record the exact trigger:
inputs, state, environment. If you cannot reproduce: gather more (logs, console,
network, data state). **Do not fix a bug you cannot reproduce** — if genuinely
irreproducible, report what you ruled out and what data would unblock it, then stop.

### 2. Minimize
Shrink the reproduction to the smallest trigger. Strip inputs field by field; drop
steps one by one. Find the boundary that flips working↔broken. If a recent change is
suspected, bisect (`git bisect run <repro-script>` when scriptable).

### 3. Hypothesize
State, in writing, ONE specific falsifiable hypothesis: *"X fails because Y, therefore
Z should show W."* Several candidates → rank and test the cheapest-to-check first.
Name the observation that would disprove it.

### 4. Instrument
Confirm or kill the hypothesis with targeted instrumentation — don't guess from reading
code alone. Temporary logs, breakpoints, assertions in the failing test. Tag every
temporary line with `# DIAG` / `// DIAG` so cleanup is greppable. Disproved → back to
step 3 with what you learned. Loop until confirmed — but **count the disproved
hypotheses**, and at three go to 4a before writing a fourth.

### 4a. Reorient — mandatory after three disproved hypotheses
Three failures is not a prompt for a fourth hypothesis. It is evidence that the frame is
wrong, and a fourth guess drawn from the same frame inherits the same blind spot. Stop
generating candidates and attack what all three shared:

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
The step-1 reproduction now passes; the full relevant suite still passes; the failing
repro is committed as a permanent regression test.

### 7. Clean up
`grep -rn "DIAG"` — remove every instrumentation line you added. The diff should
contain the fix and the regression test, nothing else.

## Output

Report: reproduction, minimized trigger, confirmed cause (with the evidence),
the fix, and verification results. If a reorientation happened, say what frame you
abandoned and what replaced it — that is the reusable lesson, more than the fix is.
If any step was skipped, say which and why.
