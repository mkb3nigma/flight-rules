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

   **Dependency scan** — when the subject is code, audit its dependency files for known
   CVEs with the ecosystem's own tool, which maps versions to advisories and covers
   transitive dependencies.

   *What leaves the machine.* Every audit below except two sends the project's package
   names and versions to a remote service — the registry (`npm`, `yarn`, `pnpm`,
   `composer`), PyPI or OSV (`pip-audit`), vuln.go.dev (`govulncheck`), and the OSV and
   NVD fallback. `cargo audit` and `bundle audit` download an advisory database and send
   no names. A project whose package names must not leave the machine says so in its
   extensions; the scan then runs only those two and reports the rest as not run.

   *Which revision.* Scan the files at the reviewed head, not whatever is checked out:
   for a range whose head is not `HEAD`, scan a detached worktree of it (`git worktree
   add --detach <tmp> <head>`, removed after), or report the scan as not run. A clean
   result for the checkout's lockfile, filed under the reviewed sha, vouches for code
   nobody reviewed.

   | File | Audit |
   |---|---|
   | `package-lock.json` / `pnpm-lock.yaml` | `npm audit --package-lock-only --json` / `pnpm audit --json` |
   | `yarn.lock` | `yarn audit --json` (Yarn 1) / `yarn npm audit --json` (Yarn 2+) |
   | `requirements.txt`, every version pinned | `pip-audit -r requirements.txt --no-deps --disable-pip --format=json` |
   | `poetry.lock` / `uv.lock` / `Pipfile.lock` | export pinned requirements with the project's tool (`poetry export -f requirements.txt`, `uv export --format requirements-txt`, `pipenv requirements`), then the row above |
   | `go.mod` | `govulncheck ./...` |
   | `Gemfile.lock` | `bundle audit check --update` |
   | `Cargo.lock` | `cargo audit` |
   | `composer.lock` | `composer audit --format=json` |
   | `pom.xml` / `build.gradle(.kts)` / `gradle.lockfile` | the OWASP dependency-check plugin, only if the build already applies it |

   `pip-audit` with no arguments audits the Python environment it runs in, not the
   project — a clean answer about the wrong packages — and `-r` without `--no-deps
   --disable-pip` resolves through pip, which can run a package's build code. So a
   `requirements.txt` with unpinned versions, or a `pyproject.toml` with no lockfile, is
   `⚠️ not run — unpinned`. `--no-deps` also means only the listed packages are
   audited: a `requirements.txt` that is not a full resolution (one written by
   `pip-compile`, `pip freeze` or a lockfile export — a hand-written one lists direct
   dependencies only) is `⚠️ partial — listed packages only, transitive not audited`,
   never clean; one you cannot tell apart is partial. A dependency file no row covers is `⚠️ not run — no mapped
   audit for <file>`, never `n/a`.

   Only a tool already installed — never install one for the review: an unpinned
   download run on the spot is the supply-chain risk the scan exists to find. With no
   tool, query [OSV.dev](https://osv.dev) per pinned package (`curl -s -X POST
   https://api.osv.dev/v1/query -d '{"package":{"name":"<pkg>","ecosystem":"<npm|PyPI|Go|Maven|crates.io|RubyGems|Packagist|NuGet>"},"version":"<v>"}'`),
   and read a critical one's CVSS from NVD
   (`https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=<CVE>`). Each result is one
   finding: `<package>@<version>`, the CVE, its CVSS as the tool, OSV or NVD gives it —
   else `CVSS: none published`, never an estimate — and the version that fixes it. The
   results get their own verdict section and reach both personas from round 2, as the
   pre-review does: given to Gilfoyle in round 1 they would land in "Gilfoyle only",
   credited to someone who found none of them. A scan that did not run is `⚠️ not run —
   <why>` in the header, never "clean": a missing tool or a refused request that reads as
   no CVEs is the silent pass §2 forbids.

2. **Independent pre-review (optional, best-effort)** — one strong reviewer, on the top
   tier where the project names tiers (step 3), looks at the subject cold: no personas,
   no access to their findings. It enumerates correctness
   bugs, security issues, design weaknesses, and unstated assumptions with severity
   (critical/important/minor) and confidence. When the subject is code, the brief carries
   § Review Domains verbatim: a reviewer starts with nothing but its brief, and a class
   it is not shown is one it is not asked to look for (group B review, 2026-10-22: no
   brief in that run carried them).

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
     same-family or unreported model (`pre-review-cli.md`, its last point), or
     `(<model>, below the top tier)` where tiers are named and the model it reports is
     below the top tier, or `(<model>, not cross-family, below the top tier)` for both;
   - `✅ <same-family reviewer> · ⚠️ <cross-family reviewer> unavailable — <why>`;
   - `⚠️ unavailable — <why>` — no pre-review counted.

   Where more than one pre-reviewer counts, the line names each, joined by ` · `, and
   every one's findings reach round 2. Every pre-review's IDs carry a prefix the
   orchestrator gives in its brief, naming its reviewer (`C1`, `F1`), with one
   pre-reviewer as with several, so round 2's answers by ID do not collide: each
   prefix distinct from the others, used by no ID in an escalated light check's record
   or register (step 3; its new rows are `L1`…), and never `A` or `D`, which the
   actions and decisions use.

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

   A project wires the concrete command for whichever CLI it has, in its extensions; this
   file states only the preference. The command names no model, sets effort to `high`,
   runs read-only with no tools, feeds the brief the way the CLI reads it, keeps the
   final message and stderr apart, and reports the model that actually ran:
   `pre-review-cli.md` beside this file gives each point's reason and an example from
   each side — read it whenever a wired CLI runs; a review with none never needs it.

   Same-family fallback is correct, and stays the default when no second model is
   reachable. A same-family pre-review still beats none — never skip the step for want
   of a second model.

3. **Spawn two persona agents** (or simulate both voices sequentially if subagents are
   unavailable): Dinesh and Gilfoyle each review the subject independently in round 1.
   Start them in the same turn as step 2's pre-review and step 1's dependency scan, not
   after: round 1 is blind to both, so waiting for them first only adds their time to
   the review's. Every persona brief says: *"Research only — read the subject and produce your
   review. Do NOT edit any files."* A persona subagent has the full toolset, and a
   reviewer that fixes what it found leaves an unreviewed change in the tree the
   verdict describes. A brief to any reviewer with a shell — a persona, step 2's
   same-family subagent — also says, and simulating both voices you keep it yourself:
   *"A probe that runs git or writes anything works in a directory it made, never in
   the repository under review: in the same script as its git commands, at its top
   level, not inside `$(…)` or a function,
   `d=$(mktemp -d) && cd "$d" && d=$(pwd -P) || exit`, and after each `git init` it
   stops unless `git rev-parse --absolute-git-dir` prints `$d/.git`, or, for a
   repository made in a folder under it, that folder's `.git`."* A reviewer's probe
   whose `cd` went nowhere ran its git commands, hooks switched off, in the repository
   under review, and switched its branch (2026-11-12). When the subject is code, each
   brief also carries § Review Domains verbatim, for step 2's reason.

   **Which tier runs which part**, where the project names its planning tier and the
   tier below (`multi-ai-setup.md` principle 6). By default there, step 2's pre-review
   runs on the top tier, as the close, cold read of the subject against its sources,
   and the two personas run on the tier below. A wired CLI runs whatever its own config
   names: that is the person's choice (`pre-review-cli.md`), the assistant does not
   edit it, and the header reports the model that ran. The preference for a
   cross-family pre-review is unchanged. Where the tool cannot start a subagent on a
   named model, each part runs on the session's model. With no tiers named, nothing
   here applies: each part runs as before. The person can
   override any of it. Why: in the 0.29.0 release review (2026-11-13/14) three
   top-tier reviewers ran every pass, the ones that only confirmed rewordings included,
   until the top tier's credits ran out and the final pass stopped; each pass's
   decisive finding came from one reviewer, and the top tier's strength showed in the
   pre-review's close reading against sources. Both halves of the split are testimony:
   which part keeps its findings on the tier below has not been measured. To measure
   it, where tiers are named the header records `> Personas: <model>` (the session's
   model where the tool could not choose one); with no tiers named, no line, nor on a
   light check that did not escalate.

   **A light check**, where tiers are named, may replace the full review of a fix's
   own diff only when all three hold: (a) every change applies a finding dispositioned
   as applied after the verdict that raised it — by the person, or by the assistant
   where the calling workflow lets it (`pr-create` 2b: after the person's reply to that
   verdict, any finding not critical) — and the register says which; (b) it changes
   nothing that a rule, refusal, check (its wiring and tests included), skill step,
   line that reaches a session, documented
   boundary or upstream-pinned claim requires or states — rewording one without
   changing what it asks or states is allowed, and so is adding a test that pins the
   finding's fix; adding, widening, narrowing or removing one of these, or any other
   test, is not — and, in code or configuration (an access policy, CORS, a workflow's
   `permissions:`, a feature flag), it changes no behaviour beyond what the finding
   names, and touches nothing that guards, gates, stores or pays, nor any dependency
   file (a manifest or lockfile: the full review runs step 1's scan); (c) no finding it
   applies was critical, or rated Major where the project rates findings, by any
   reviewer or in the verdict. Anything else gets the full review, and so does every
   fix where no subagent can be started: its reviewer would not be cold.

   The orchestrator runs it, and the header names it and why:
   `> Review: light check (<model>) — <why it qualifies>`, under
   `## Review: <subject>`. The person can ask for the full review at any time. One
   reviewer on the tier below reads it cold — no debate, no earlier review: the diff,
   the files it touches as they stand at the head, its commit messages as claims to
   check, not answers, and (a)–(c) as written. For (a) and (c) the brief names the
   rounds that ran and every reviewer in them — each pre-reviewer, each persona per
   round, the verdict — and quotes the record verbatim, each quote marked with its
   source: per applied finding, for each of those, the row that rated it or "did not
   rate it", and its disposition as recorded — the person's reply, or the PR body; for
   the assistant's with no PR body yet, the person's reply that released the verdict
   and the assistant's disposition, marked as the assistant's. A paraphrase or a
   missing entry puts that condition in doubt. The brief also carries what every
   brief here does: the no-edit and probe lines above, § Review Domains for code, and
   the project's extensions. Its `## Verdict` is one register: a row per condition,
   `holds`, `does not` or `in doubt`; a row per applied finding, `landed`, `not landed`
   (no change made for it) or `beyond` (a change past it, or one that claims it and
   misses); each value that word alone, its reason beside it; then `New`, a row per
   new finding numbered `L1`, `L2`…, or `New: none`. The brief asks for
   `LIGHT CHECK COMPLETE: <n> new` as its last line, verbatim and unformatted, `<n>`
   the count of `L` rows, `0` included, read as step 2 reads a subagent's: the last
   non-empty line of its own reply. The line shows only that the reply reached its
   end. The register is complete only with that line; exactly one row for each of
   (a)–(c) and exactly one for each applied finding the brief names, by its ID, and
   for no other, each holding one of its words; `New`; nothing else in the reply but
   the `## Verdict` heading; and `<n>` equal to the `L` rows. The orchestrator checks
   this against the brief it wrote, and never takes it from the reviewer; whether each
   row is true is the reviewer's judgment, which no such check reaches, and that is
   the risk accepted. A complete register passes only if every condition reads
   `holds`, every finding `landed` or `not landed`, and `<n>` is 0: then
   `## Decisions waiting` follows, the not-landed findings in it, `(0)` included, and
   the turn ends, as at step 5. Otherwise, or with no reply within `DG_WAIT_MINUTES`
   (step 4), it escalates: the full review runs on the same diff in the same turn, and
   the reply is that review, its one `## Review:` header carrying
   `> Review: light check (<model>) escalated — <why>`, and the register printed once,
   as the verdict's `### Light check`, not on its own before it. An incomplete one is
   printed as given, inside a fence longer than any backtick run in it (step 6's
   rule), under `incomplete — <what is missing>`; with no reply, `### Light check`
   holds the `<why>` alone, and a reviewer still running at the limit is stopped, as
   step 4 stops a pre-reviewer. The register, complete or not, reaches the personas
   from round 2, as a pre-review's findings do; its not-landed rows join that review's
   `## Decisions waiting`, still the reply's last section. A light check that did not
   escalate has no rounds, personas, pre-review line, scan or comic: the review that
   raised a finding scanned what the fix leaves unchanged. In a PR body (`pr-create`
   2b) the header line and the verdict go in as a full review's do, headings one
   level down: `### Verdict`, `#### Light check`.

4. **Debate loop** (default 5 rounds) — Round 1: Dinesh presents → Gilfoyle responds.
   **Round 2 waits** until every pre-reviewer started — the cross-family one, its
   same-family fallback, any other a project's extensions wire — has finished or
   failed by step 2's check, and the dependency scan has reported. A pre-reviewer
   left running in the background while the debate went on finished after the verdict,
   and its findings reached no round (2026-10-18). The wait has a limit,
   `DG_WAIT_MINUTES` in the conf (default 15; read like step 6's keys):
   a run with no result that long after it started is stopped and counts as failed —
   step 2's fallback, then `⚠️ unavailable — no result in <n>m` (for the scan, `⚠️ not
   run — no result in <n>m`). A timeout an extension gives its own pre-reviewer is an
   inner limit under this one, so the extension need not read the key: a shorter one
   fails that run sooner, a longer one is cut off here. Round 2's table then
   answers each pre-review finding by its ID, each scan finding by its
   `<package>@<version>` and CVE, and each row of an escalated light check's register,
   and Gilfoyle's harshest finding → Dinesh defends or concedes. Further rounds
   alternate who leads. Converge early when concessions leave nothing disputed, but
   never before round 2 has answered the pre-review, the scan and an escalated light
   check's register: a debate that converges in round 1 is the debate that ends
   before they arrive.

5. **Verdict** — merged summary: findings both agreed on, findings that shifted
   severity, each side's solo findings, pre-review-only findings (so nothing is
   silently dropped), an escalated light check's register (step 3), the dependency
   scan's results and concrete recommended actions.
   It goes to the person in the format below — step 6's comic after the header, the
   decisions waiting last — and **the turn ends there**: apply no finding and run no further
   step of a calling workflow (such as `pr-create` 2b) until the person replies. A
   verdict printed and then fixed past in the same reply is the skip again, in a
   different order. The 0.25.0 release review went straight from the debate to fixes:
   the verdict reached only the PR body, and the comic was never offered (2026-10-17).

6. **Comic strip, first** — two settings in the conf (`.flight-rules/conf`, or
   `.ai/flight-rules.conf` where that is absent), read like every
   other key there (unset, no conf, or any other value: the default — `flight-rules-doctor.sh`
   warns about the value):
   - `DG_COMIC` — `always` (default) or `never`. With `always` the reply carries the
     comic as ASCII art, never offered: an offer at the end of a step list was skipped
     (2026-10-17). With `never` there is no comic and no banter score anywhere.
   - `DG_COMIC_PR` — `never` (default), `ask` or `always`: whether the comic, banter
     score included, goes into the PR when the review is for one (`pr-create` 2b, or the
     person says so). Strictly opt-in: `never` keeps it out without asking; `ask` puts
     *"Add the comic to the PR? (y/N)"* as the reply's last line; `always` adds it as
     `### Comic` at the end of the PR's review section. Nothing else carries the comic
     or the score into a PR, issue or commit: the owner added both for levity, and not
     every reader shares the taste (2026-10-17). Ignored when `DG_COMIC=never`.

   A light check that did not escalate (step 3) has no comic: it has no rounds.

   The comic: up to 8 panels of the best banter, at least one per round, in a block
   fenced with more backticks than any run inside it (a quoted ` ``` ` would close a
   shorter fence), each a box headed `[N] GILFOYLE` or `[N] DINESH` with a small ASCII
   face and the quote, then the banter score and one line per verdict finding tagged
   `[AGREED]`, `[CONTESTED]` or `[DISMISSED]` (the rules below). It comes right after the
   header, before the rounds: a terminal shows a reply's end, and with the comic last the
   owner scrolled back past it for the decisions — "while the banter is fun, it seems to
   overshadow the actual content" (2026-10-24).

   **A page, on request only.** If the person asks for the comic as a page or a PNG,
   `comic-page.md` beside this file says how; a copy of this skill without it says so.
   Either stays local: a PR gets the ASCII comic, under `DG_COMIC_PR`.

## Personas (condensed)

**Dinesh** — cautious optimism; built most of this and wants credit for what works.
Defends decisions with reasons but folds under real pressure; self-deprecating banter;
concedes immediately on auth bypasses, exposed secrets, injection, or a missing revenue
mechanism. Tags findings `[defend]` / `[concede]` / `[agree]` / `[nitpick]`; every
`[defend]` gets a one-sentence justification.

**Gilfoyle** — reviews like a pathologist performs an autopsy. Never praises; "no
critical issues" is his highest compliment. Business realist: cites real competitors,
runs rough revenue numbers to expose magical thinking; flags assumptions stated as
facts. Tags findings `[dismiss]` (rejects Dinesh's defence) / `[escalate]` /
`[concede]` / `[new]`; every
`[escalate]` gets a justification. Finds real issues only: a finding made up to fill
the table costs the owner a fix for nothing, and when the subject is sound he says so
in as few words as it pains him to.

Both output per round: a one-line in-character **BANTER** (never aimed at the user) and
a findings table: `| # | Location | Finding | Dimension | Severity | Tag | Verified? | Fix |`.

## Output Format

Every stage reports as a register, not as prose (`engineering-principles.md` §7) — the
pre-review included, which is otherwise the one stage with no prescribed shape and the
place a long verdict turns back into paragraphs.

````markdown
## Review: <subject>
> Review: light check (<model>) — <why it qualifies> | light check (<model>) escalated — <why>   (a light check only, step 3; one that did not escalate has no other header line, no comic and no personas)
> Pre-review: <one of the forms in step 2>
> Dependency scan: ✅ <tool> — <n> findings | ⚠️ not run — <why> | n/a (no dependency files, or not code)
> Personas: <model>   (where tiers are named, a full review, step 3)

## Comic
```
<the ASCII strip — step 6: panels, banter score, one tagged line per finding>
```

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
### Light check (only when one escalated: its register, fenced and marked incomplete where it is, or the `<why>` alone where no reply came; step 3)
### Dependency scan
### Recommended Actions
A1. <the action>

## Decisions waiting (<n>)
D1. **<the decision>** — what it is, why it came up, the evidence, what each option
   costs, and the recommendation: decidable from this item alone.

Add the comic to the PR? (y/N)
````

A light check that did not escalate (step 3) has no `## Comic` section, whatever
`DG_COMIC` says.
The `## Comic` section is absent with `DG_COMIC=never`, and the last line appears only
with `DG_COMIC_PR=ask` on a review that is for a PR. The decisions are the reply's last
section — only that optional line follows them — where a reader in a terminal lands;
a list numbered D1, D2…, as the actions are A1, A2…, so a bare number in an answer
means one item (2026-11-12) — not a table, because each one is sentences, and a table
of sentences wrapped past reading at terminal width (2026-10-24). With none, the section says so: `## Decisions waiting (0)`. Last, as
`engineering-principles.md` §7 puts them: a verdict runs to screens, and its first
screen is the one scrolled past. Each decision is decidable from its item alone, as §7
asks.

`## Verdict` ends at Recommended Actions (a light check's that did not escalate is its
register), so wherever a PR body takes "the verdict", it takes neither the comic, nor
the round tables' BANTER lines, nor the decisions (the PR body records each finding's
disposition instead); the comic follows only by `DG_COMIC_PR`.

**Banter score** is a tongue-in-cheek tally of who won the arguments — banter, not a
measure of the work, and it lives in the comic, ahead of the findings and kept out of
them, because it decides nothing; they do. Only a finding one persona raised and the other argued counts: Gilfoyle's if
Dinesh conceded it under pressure or a `[defend]` broke, Dinesh's if his `[defend]`
held or Gilfoyle `[concede]`d. Gilfoyle's `[dismiss]` (rejecting Dinesh's defence)
scores nothing by itself: the point goes to whichever way the defence then went. Unscored: findings both
`[agree]` on, nobody argued, a persona raised against their own side, or that came from
the pre-review, the scan or a light check. The orchestrator scores at the verdict; the personas are
never told the rule, so no one defends a point to win it.

**Location** is `file:line` for code, the section or claim otherwise. **Verified?**
distinguishes a finding the reviewer reproduced by running something from one it
reasoned to. A reader deciding what to fix first needs that column more than any
other, and a reviewer who cannot fill it has said something weaker than it sounds.

## Review Domains

Adapt to the subject. For code, look for each class below that the diff gives a reason
to. A finding names its place (`file:line`) and, where a test should have caught it,
the test that would fail. A class with nothing found is not reported: the table holds
findings, not a checklist. The classes' warrant: an adopter found body ids its ownership
sweep missed, which this list's generic "security" had not named (2026-10-21).

- **Security** — *object-level authorization*: a record id a caller supplies (path,
  body, nested arrays, tool or RPC arguments) with no ownership check, or an ownership
  check no test exercises; a foreign id answered differently from an unknown one (an
  existence oracle); a test that fails for an unrelated 404/422, not for ownership. The ids are
  best listed from the schema, not by hand. *Untrusted input*: SQL built as a string,
  shell, templates, file paths, URLs fetched server-side. *Client-side*: unescaped HTML,
  CSRF on cookie-authenticated changes, secrets in bundles. *Fail-open defaults*: a
  missing config value, flag or permission that allows. *Shared policies*: one setting
  serving two principals' security policies, so tightening one moves the other.
- **Correctness** — *races*: check-then-act, double submit, a handler unsafe to run
  twice with no unique constraint, module-level mutable state shared across requests or
  workers. *Magic values*: a literal compared where an enum, union or named constant
  exists, or a fixed-value field typed as a plain string — a typo should fail the build,
  not run; a value from outside the app stays untyped until a type guard narrows it,
  never a cast. *Swallowed errors*: a catch that neither handles a named failure nor
  surfaces it. *Dropped async errors*: a promise or task neither awaited, returned nor
  handled. *Time*: an instant stored without a zone; calendar arithmetic (next day,
  9am local, a recurrence) done in UTC or server time, not the owning zone.
- **Performance** — *unbounded work*: no limit or pagination, no size cap on input.
  *Blocking calls* in async code.
- **Compatibility** — an API, schema, config key or CLI change that breaks existing
  callers or stored data; deploy order (old code on a new schema).
- **Tests** — a changed behaviour no test would fail without; an assertion that passes
  on no output; a harness that can reach a non-disposable database (it should refuse
  before connecting).
- Where the code has them: data access (missing indexes, N+1 queries, transactions,
  migrations), distributed calls (timeouts, retries with backoff, idempotency, partial
  failure), logging (secrets or PII in logs, silent critical paths), and the language's
  own idioms.

Otherwise: architecture (coupling, scale, reversibility), product/business (market fit,
monetisation mechanics, churn, distribution), decisions (trade-offs, alternatives,
assumptions, reversibility).
