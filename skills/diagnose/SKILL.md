---
name: diagnose
description: Structured debugging loop — reproduce, minimize, hypothesize, instrument, fix, verify, clean up. No fix without a reproduction.
---

# /diagnose — Structured Debugging Loop

Debug a reported bug methodically: reproduce → minimize → hypothesize → instrument →
fix → verify → clean up. Never jump straight to a fix.

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
step 3 with what you learned. Loop until confirmed.

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
the fix, and verification results. If any step was skipped, say which and why.
