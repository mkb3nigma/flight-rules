# /pr-create — the release PR, steps 2a and 2b

Read by `/pr-create` for a release PR only: the head is `{INTEGRATION_BRANCH}` and the
base is `main`. Step 2 and 3's template are SKILL.md's.

## Why

- A release PR (`{INTEGRATION_BRANCH}` → `main`) additionally needs the full
`{TEST_COMMANDS}` run on the commit being pushed — step 2a. Warrant: AppliHawk's
release PR #191 went red on its first CI run on 2026-09-14 with every merged branch
individually green, because five merges landed after the batch run and the integration
branch was never tested whole.
- A release PR also needs `/dg` on the **whole** diff, `origin/main...<sha>` — step 2b —
with the verdict and every finding's disposition in the PR body; where the project
runs flight-rules' `release review` workflow (`.github/workflows/release-review.yml`),
it fails a PR into `main` whose **Adversarial review** section is missing or empty. Warrant: AppliHawk's
0.16.0 was declared release-ready on 2026-10-11 with every branch past
`/pre-merge-check` (which runs no AI review) and the suite green on the final
integration commit; `/dg` on the 93-commit, 224-file diff the next day found a
data-loss bug — editing an action unlinked its contact, because a nested response
schema was a hand-copied subset of the full one and the component test's fixture was
shaped like the frontend type, not the API payload (fixed in AppliHawk aa4ca42e,
2026-10-12; private repo). Nothing had reviewed the release as a whole, and the whole
is the one review with every piece in view at once.

## The steps

2a. **Release PR only** — when the head is `{INTEGRATION_BRANCH}` and the base is `main`:
   before pushing it, run every `{TEST_COMMANDS}` entry on the **exact commit that will
   be pushed**, and stop on any failure. Report the commit sha you ran them on, not just
   that you ran them — "I ran the suite" and "I ran the suite on the commit I am pushing"
   are different claims, and only the second is checkable.

   Per-branch checks prove each change in isolation; the release PR ships the **sum**.
   Nothing has tested the sum until something runs everything on the merged tree. A red
   offline run costs the same minutes as a red CI run and none of anyone's attention.

   A local run covers one platform. Where CI runs the suites on more, push, then read CI's result
   for that same sha (`gh run list --commit <full sha>` — a short sha matches no run,
   and an empty list has nothing red in it; the final 0.25.0 review). It lists workflow
   runs, not platforms: a matrix of OSes is one run, its conclusion covering every job
   (`gh run view <id>` names each). Open the PR only when each workflow CI runs on a
   push is listed for that sha, completed and green — none listed means not yet. 0.25.0's 2a passed on macOS (bash 3.2) while Ubuntu CI
   (bash 5) had been red on `{INTEGRATION_BRANCH}` for two pushes (flight-rules
   4fe21fe, 2026-10-17).
2b. **Release PR only** — run `/dg origin/main...<sha>` on the commit 2a tested,
   preferring a pre-reviewer from a different model family (the skill says why; one
   that is unavailable is a warning in the verdict's header, not a reason to stop), and
   name both shas in the verdict. `/dg` ends its turn with the verdict; dispositions
   follow the owner's reply. Put the `> Pre-review:` / `> Dependency scan:` lines, the verdict (it ends at
   Recommended Actions) and every finding's disposition in the PR body under
   **Adversarial review**, each of the verdict's headings one level down (`###`, `####`;
   the review's own `## Review` title too)
   — a `##` inside the section ends it (outside a code fence), and the check below then finds it empty. No
   round tables or banter. The comic, banter score included, goes in only as the
   project's `DG_COMIC_PR` says (`/dg` step 6; default `never`), as `### Comic` at the
   section's end. Where the project runs it, the `release review` workflow checks the section is there, holds text
   other than the template's placeholders, and holds a `### Verdict`, outside a code
   fence, with text under it that is not a heading — the header lines alone are not a
   verdict (#83), nor is a bare heading — and re-checks on every body edit. The assistant may decline a minor or important finding with its reason, where the
   owner reads it; a **critical** finding is the owner's to disposition — stop and
   ask. A finding applied arrives like any change, through a branch merged into
   `{INTEGRATION_BRANCH}`; then 2a runs again on the new tip, and `/dg` on the fix's
   own diff only — the rest was reviewed, and that is the exit.

   The same reasoning as 2a, for review instead of tests (the warrant is under
   *Why* above): each branch was checked as a piece, and the release diff is the
   one review with every piece in view at once.

   The body also states what the release adds, by class, from `git diff --numstat
   origin/main...<sha>` — added and net lines by the classes the project's own rules
   name (its `CLAUDE.md` or an `EXTENSIONS.md`): what reaches a session, hook and guard
   code, tests, CI, and everything else, the five summing to the total. The count is evidence,
   not a gate: whether it is proportionate to what the release closes is the owner's
   call, made with the CHANGELOG entry beside the number. flight-rules 0.27.0 added
   4,554 lines, 4,071 of them hook and test code, and no gate recorded the number.
