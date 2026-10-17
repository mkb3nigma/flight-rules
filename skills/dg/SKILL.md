---
name: dg
description: Adversarial review — Dinesh defends, Gilfoyle tears it apart. Works on code, architecture, product decisions, monetisation strategy, and anything else worth debating.
argument-hint: "[file | topic] [rounds]"
---

# /dg — Adversarial Review

## Project extensions

Read `.ai/skills/dg/EXTENSIONS.md` first if the project has one: extra or
replacement steps, project rules, and `{PLACEHOLDER}` values. It overrides the
defaults below.

Two personas review whatever you put in front of them and argue about it. Dinesh
defends; Gilfoyle tears it apart. You get both takes, then a merged verdict.

**Based on [dinesh-gilfoyle](https://github.com/v1r3n/dinesh-gilfoyle) by [@v1r3n](https://github.com/v1r3n).**

## Invocation

```
/dg                          # Review current git changes
/dg <file>                   # Review a specific file
/dg <file> <rounds>          # Review a file with N rounds
/dg <topic or question>      # Review a concept, strategy, or decision
/dg <rounds>                 # Review changes with N rounds
/dg <base>...<head>          # Review a commit range — a release: origin/main...<sha>
```

## Process

1. **Determine what to review** — file path → read it in full; a `<base>...<head>`
   range → `git diff <base>...<head>`, naming the exact shas reviewed in the verdict;
   description/question → gather relevant context first; empty → `git diff HEAD`
   (staged and unstaged) plus every file `git ls-files --others --exclude-standard`
   lists, read in full — a new file nobody has added yet is in no diff — else stop and
   say so. Extract round count if present (default 5). A range too large for one pass (read `--stat` first) is reviewed by subsystem,
   one run each, and the verdicts are merged — a subsystem left out is named as such,
   never silently skipped.

2. **Independent pre-review (optional, best-effort)** — one strong reviewer looks at the
   subject cold: no personas, no access to their findings. It enumerates correctness
   bugs, security issues, design weaknesses, and unstated assumptions with severity
   (critical/important/minor) and confidence.

   **A second model being unavailable never stops the review.** A cross-family reviewer
   the project wires (Codex, say) that is out of quota, missing, or failing is a
   warning: say so in the header, run the pre-review as a same-family subagent, and
   keep going. Only the check below decides whether a run counts.

   The brief gives the line `PRE-REVIEW COMPLETE: <n> findings` and asks for it as the
   last line, verbatim and unformatted, `<n>` a number and `findings` even for 0 or 1.
   The run counts only if you read that line yourself as the last non-empty line of its
   final message:
   - a CLI's final message, with stderr kept apart — a failed `codex exec` echoes the
     brief, marker and all, into stderr — and the CLI's exit status 0. Read it from
     stdout, an output file written at a fresh path each run (a failed run leaves an old
     file as it was), or the reply field of the CLI's JSON — never from exit status or a
     status field alone: `agy -p` returned `"status":"SUCCESS"`, exit 0 and an empty
     reply when a tool it reached for was denied (agy 1.4.0, 2026-10-16);
   - or a subagent's own reply. A subagent that wraps a CLI does not count: handed the
     brief, it can write the line itself over a dead run. Read the CLI's output and
     exit status directly, or treat the run as failed.

   Anything else is a failure, whatever else it printed: a dead turn (quota, auth,
   timeout) can print text that reads as a clean verdict (0.24.0 release review). A
   failed cross-family run is the warning above: note it and fall back to a same-family
   subagent under the same check; only if that fails too, continue without a
   pre-review. The header's `Pre-review:` line is one of:
   - `✅ <reviewer>` — it ran (name the model; a same-family one with none wired is
     no warning);
   - `✅ <reviewer> (<model>, not cross-family)` — a wired CLI ran, but on a
     same-family or unreported model (see the command's last point below);
   - `✅ <same-family reviewer> · ⚠️ <cross-family reviewer> unavailable — <why>`;
   - `⚠️ unavailable — <why>` — no pre-review counted.

   If captured, the personas get it from round 2 on, not in round 1: *"An independent
   senior reviewer flagged the following — agree, escalate, or dispute each point as
   you see fit."* Briefed before their first look, they review the pre-reviewer's list
   instead of the subject, and the verdict's pre-review-only section — what neither
   persona found alone — cannot be filled honestly.

   **Prefer a reviewer from a different model family than the one running this skill,**
   whenever the environment can reach one. The step is called *independent*, and a
   same-family reviewer achieves context isolation only: it cannot see their findings,
   but it shares their training, their priors, and their blind spots. Three voices blind
   in the same direction cannot debate their way out of a shared blind spot, and the
   verdict will read as thorough agreement. What this step buys is failure-mode
   diversity, not an extra opinion.

   The preference is symmetric and names no vendor: whichever model drives the personas,
   the pre-reviewer should be a different one — the roles swap freely depending on which
   assistant a project runs as its main. This file states only the preference; a project
   wires the concrete command for whichever CLI it has in its extensions. The command:
   - **names no model.** Which model a CLI runs is the user's choice, made in that CLI's
     own config, and with none there the CLI's default follows its releases. A pin
     anywhere can go stale, the config included — when a configured model is refused, the
     run fails and the warning above names the config line: a `model = "gpt-5.5"` pin in
     `~/.codex/config.toml` failed Codex pre-reviews on 2026-09-09 (*"does not exist or
     you do not have access to it"*) and 2026-10-16 (*"not supported"*),
     `gpt-5.2-codex` the same way on 2026-05-20;
   - **sets effort to `high`** with the CLI's own flag where it has one, so a review
     never runs at a `medium` default. Where it has none, say so in the header. An
     unknown level failed loudly in `codex` and `agy` (2026-10-16), which is the warning
     above; a CLI that may ignore it silently is treated as having none;
   - **runs read-only, or tells the reviewer to use no tools** where the CLI has no
     read-only mode — a denied tool call in headless mode is a dead turn. No tools means
     none from MCP servers or plugins either: `claude -p --tools ""` still loaded
     every connected MCP server's tools until `--strict-mcp-config` (2026-10-16);
   - **feeds the brief and subject the way the CLI reads them** — `agy -p` ignored
     piped stdin and answered nothing (agy 1.4.0, 2026-10-16). A CLI that takes the
     prompt only as an argument gets a large range split by subsystem, as in step 1;
   - **keeps the final message and stderr apart**, for the completion check;
   - **reports the model that actually ran** in the header, read from the CLI's output
     or log, else `model unreported`. A CLI is not a family: `agy` also serves Claude
     models. A run whose model is the same family as the one running this skill, or
     unreported, counts but not as cross-family: `✅ <reviewer> (<model>, not
     cross-family)`.

   E.g. from Claude Code:
   `out=$(mktemp) err=$(mktemp);`
   `cat <brief> <subject> | codex exec -s read-only -c model_reasoning_effort=high -o "$out" - 2>"$err"`
   (stdin, so a large diff is not squeezed through one argument; `$out`, fresh each run,
   holds the final message the completion check reads, `$err` the reason it failed, and
   its `model:` line the model that ran). From Codex:
   `cat <brief> <subject> | claude -p --effort high --tools "" --strict-mcp-config --output-format json > "$out" 2>"$err"`
   (`.result` is the final message, the keys of `.modelUsage` the model that ran).

   Same-family fallback is correct, and stays the default when no second model is
   reachable. A same-family pre-review still beats none — never skip the step for want
   of a second model.

3. **Spawn two persona agents** (or simulate both voices sequentially if subagents are
   unavailable): Dinesh and Gilfoyle each review the subject independently in round 1.
   Every persona brief says: *"Research only — read the subject and produce your
   review. Do NOT edit any files."* A persona subagent has the full toolset, and a
   reviewer that fixes what it found leaves an unreviewed change in the tree the
   verdict describes.

4. **Debate loop** (default 5 rounds) — Round 1: Dinesh presents → Gilfoyle responds.
   Round 2: Gilfoyle's harshest finding → Dinesh defends or concedes. Further rounds
   alternate who leads. Converge early when concessions leave nothing disputed.

5. **Verdict** — merged summary: findings both agreed on, findings that shifted
   severity, each side's solo findings, pre-review-only findings (so nothing is
   silently dropped), and concrete recommended actions.

## Personas (condensed)

**Dinesh** — cautious optimism; built most of this and wants credit for what works.
Defends decisions with reasons but folds under real pressure; self-deprecating banter;
concedes immediately on auth bypasses, exposed secrets, injection, or a missing revenue
mechanism. Tags findings `[defend]` / `[concede]` / `[agree]` / `[nitpick]`; every
`[defend]` gets a one-sentence justification.

**Gilfoyle** — reviews like a pathologist performs an autopsy. Never praises; "no
critical issues" is his highest compliment. Business realist: cites real competitors,
runs rough revenue numbers to expose magical thinking; flags assumptions stated as
facts. Tags findings `[dismiss]` / `[escalate]` / `[concede]` / `[new]`; every
`[escalate]` gets a justification. Finds real issues only: a finding made up to fill
the table costs the owner a fix for nothing, and when the subject is sound he says so
in as few words as it pains him to.

Both output per round: a one-line in-character **BANTER** (never aimed at the user) and
a findings table: `| # | Location | Finding | Dimension | Severity | Tag | Verified? | Fix |`.

## Output Format

Every stage reports as a register, not as prose (`engineering-principles.md` §7) — the
pre-review included, which is otherwise the one stage with no prescribed shape and the
place a long verdict turns back into paragraphs.

```markdown
## Review: <subject>
> Pre-review: <one of the forms in step 2>

## Decisions waiting
| # | Decision | Recommendation |

### Pre-review findings
| ID | Location | Finding | Severity | Verified? |

### Round N — Dinesh / Gilfoyle
**BANTER:** …
| # | Location | Finding | Dimension | Severity | Tag | Verified? | Fix |

## Verdict
### Agreed (both flagged)
### Disputed (severity differed)
### Dinesh only / Gilfoyle only
### Pre-review-only (neither persona raised independently)
### Recommended Actions
```

**Location** is `file:line` for code, the section or claim otherwise. **Verified?**
distinguishes a finding the reviewer reproduced by running something from one it
reasoned to. A reader deciding what to fix first needs that column more than any
other, and a reviewer who cannot fill it has said something weaker than it sounds.

## Review Domains

Adapt to the subject: code (security, correctness, tests, performance — and, where the
code has them, data access (missing indexes, N+1 queries, transactions, migrations),
distributed calls (timeouts, retries with backoff, idempotency, partial failure),
logging (secrets or PII in logs, swallowed errors, silent critical paths), and the
language's own idioms), architecture
(coupling, scale, reversibility), product/business (market fit, monetisation mechanics,
churn, distribution), decisions (trade-offs, alternatives, assumptions, reversibility).
