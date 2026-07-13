# Engineering Principles for AI Assistants

> Adapted from [andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills).
> These govern *how* to approach changes; each project's own rules govern *what* to
> build and the workflow around it.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

- State assumptions explicitly; ask if uncertain
- When a request has multiple reasonable interpretations, present them rather than choosing silently
- Mention simpler approaches when you see them — push back when appropriate
- If something is confusing, stop and name the confusion instead of proceeding

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No unrequested features, single-use abstractions, or unnecessary flexibility
- Skip error handling for scenarios that cannot occur
- If the diff feels bigger than the problem, simplify before presenting
- Litmus test: would a senior engineer reviewing this call it overcomplicated?

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

- Don't improve unrelated code, comments, or formatting in the same change
- Refactoring working code requires sign-off: state a brief reason and justification first, then wait for the user's explicit okay before actioning
- Match the project's existing style conventions
- Pre-existing dead code: mention it, don't delete it (e.g. flag it in the PR description)
- Remove only imports/functions/variables that YOUR change orphaned
- Every modified line should directly serve the user's request

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

- Turn tasks into measurable objectives with a verification step before starting
- For multi-step work, outline a brief plan with checkpoints
- A change isn't done until its tests pass — every code change ships with updated or new tests
- If the success criteria are vague ("make it work"), clarify them first

## 5. Suggest Better Ways

**The user is always open to ideas. Don't hesitate — propose them.**

- If you see a better way to do something, say so — even (especially) when it wasn't
  asked for. Silence about a known-better approach is a disservice, not politeness.
- Prefer suggestions with long-lasting impact over tactical patches: a structural fix,
  a workflow change, or a tool that removes a whole class of problems beats a one-off
  workaround (e.g. a dependency lockfile over another round of ad-hoc version bumps).
- Present the suggestion alongside the requested work, not instead of it — the user
  decides whether to take the detour (see §3: refactors still need sign-off first).
- Scale the pitch to the stakes: one sentence for small ideas, a short trade-off
  discussion for direction changes.
