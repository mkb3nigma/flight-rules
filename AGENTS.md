# flight-rules — working in this repo

This is the playbook itself, so it follows its own rules. Read `MISSION.md` first: it
says what flight-rules is for, and a change here answers the questions of it that apply
before it is judged on anything else. It loads only here — adopting projects never see
it. Then `rules/` — every file, they are short — and treat them as binding here:
`engineering-principles.md` for how to make a change, `git-worktree-workflow.md` for
branching. A session-start hook may inject the principles; the rest you read once. This
file is for every assistant; `CLAUDE.md` and `GEMINI.md` import it.

## Parameters

`.flight-rules/conf` is the single home for the branch policy. It also sets
`DG_COMIC_PR=always`: this repo's release PRs carry the `/dg` comic, to show it in use
(the default elsewhere is `never` — `hooks/README.md` → Configuration). Summary:

| Parameter | Value |
|---|---|
| `{PROTECTED_BRANCHES}` | `main` and `dev` — no direct commits to either |
| `{PR_ONLY_BRANCHES}` | `main` — no local merges; it moves only through a reviewed PR |
| `{NOTE_GATED_BRANCHES}` | `dev` — a local merge needs a `pre-merge-check` note on the branch being merged |
| `{INTEGRATION_BRANCH}` | `dev` — work integrates here; `main` is the released state |
| `{WORKTREE_DIR}` | `.flight-rules/worktrees/` (git-ignored) |
| `{TEST_COMMANDS}` | `hooks/agent/pre-commit-check.test.sh`, `hooks/agent/session-start.test.sh`, `hooks/git/merge-gate.test.sh`, `hooks/git/ref-gate.test.sh`, `hooks/git/secret-scan.test.sh`, `hooks/git/install.test.sh`, `hooks/flight-rules-doctor.test.sh`, `hooks/wiring.test.sh`, `skills/catalogue.test.sh`, `docs-consistency.test.sh` — no arguments, no network |

Every change: `/feature-start <prefix>/<slug>` — `git fetch origin`, origin pulled into
local `dev`, the open-branch count (`OPEN_BRANCH_LIMIT`, asked at the limit), then `git
worktree add .flight-rules/worktrees/<slug> -b <prefix>/<slug> dev`; a raw `worktree add` skips the
count — and commit there; the owner pushes it. Then, **as the owner** (the assistant
too, under the standing OK below), merge it into `dev` locally — stamp the
`pre-merge-check` note on the branch tip and `FLIGHT_RULES_MERGE_AUTHORISED=1 git merge`
from the `dev` checkout; the owner pushes `dev` when ready, at the latest for the
release. No PR: `dev` is note-gated, not PR-only, and the
local merge is what exercises the note gate, the authorisation trailer and the back-merge
exemption — a GitHub-button merge runs none of them. **A contributor** cannot push `dev`
and opens a PR to it instead. `main` is PR-only for everyone. Never commit on `main` or
`dev`; sync with `git pull --ff --no-rebase origin dev`.

An assistant pushes no branch, and runs no `/pr-create` (which pushes), unless the
owner says so in that session — the owner reviews and pushes (standing instruction).
The assistant may run the local merge into `dev` without asking, once a real
`/pre-merge-check` on the branch tip has passed and stamped it: this standing OK (owner,
2026-10-26) is the user's instruction that `git-worktree-workflow.md` Forbidden 8 and
`pre-merge-check`'s closing line ask for. `main` still moves only through the reviewed
promotion PR.
A branch that has fallen behind `dev` or conflicts with it gets `dev` merged **into**
it, is tested and stamped there, then merges back. The conflict is never resolved in
the merge into `dev`, where the note would vouch for a tip that never held the
resolution. Merge, not rebase (owner's preference, 2026-10-05).

**`main` moves at a release, not per change.** A promotion is one PR, `dev` → `main`,
carrying one version bump, the full `{TEST_COMMANDS}` run on the exact commit being
pushed (`pr-create` step 2a — the per-branch checks proved the pieces, not the sum), a
`/dg` verdict on the whole `origin/main...<sha>` diff with each finding's disposition
(step 2b — the one review with every piece in view at once: AppliHawk aa4ca42e,
2026-10-12, a data-loss bug every branch gate had passed; the `release review` check
fails a PR into `main` without the section, or without a `### Verdict` in it), and a summary of what the batch did — so
the published history is releases, not a debugging session. Both branches are protected on GitHub (PR required
on `main`, CI required on both, force-push and deletion blocked); admins are exempt, which
is the emergency path for a genuine bug in a release, taken deliberately and reviewed hard.

Feature PRs to `dev` **do not touch `.claude-plugin/plugin.json`** — the bump belongs to
the release. Bumping per feature is how three stacked PRs came to conflict on that one
line while GitHub reported all three mergeable.

**Releasing.** The version bump is a change like any other, so it arrives through a
branch and a PR — `dev` is protected and the promotion PR's head *is* `dev`, so there is
nowhere else to put it. Bump `.claude-plugin/plugin.json` and add the CHANGELOG entry on
a `chore/release-<v>` branch, merge that to `dev`, then open the promotion PR: run
`/upstream-check` (its report under `## Upstream check` in the PR body), then
`pr-create` step 2a (every `{TEST_COMMANDS}` entry on the exact commit being
pushed, reporting the sha), then 2b (`/dg origin/main...<that sha>`, verdict and
dispositions in the PR body, with the release's added and net lines by class — `MISSION.md`
question 3's count, each file in the first class it matches: tests = `**/*.test.sh`;
hooks = `hooks/**` minus `*.md`, `*.json`; CI = `.github/**`; session-reaching = `rules/**`, `skills/**` (a body and the files beside it, read on its pointer as `rules/` is),
`.ai/skills/**`, `.claude/skills/**`, `MISSION.md`, `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`; other = the rest, the five summing to `--numstat`'s total —
and the five questions asked of each subsystem; a critical finding is the owner's call; a finding applied
arrives through a branch merged to `dev`, then 2a again on the new tip and `/dg` on the
fix's own diff), then — last, on the final head, once 2b has nothing left to apply —
`mutation/run.sh -j 4` from a worktree of it, and the stamp it writes pushed
(`git push origin refs/notes/mutation`, printed by the run; the `release review` check
requires a clean stamp on the PR's head, so a commit after it means running it again,
and an assistant never writes one by hand — `mutation/README.md`), and `--base main`. That promotion is the one PR whose head is
a protected branch, which `pr-create`'s constraint names as its only exception.

## Which model does what

`rules/multi-ai-setup.md` principle 6 applies here: the top tier of each family plans,
designs and reviews, and hands implementation to the tier below through an issue that
carries the plan (owner, 2026-11-11). At the time of writing that is Fable for
Anthropic, Sol for OpenAI and Argon for Google; the owner can override it for any task.
In `/dg` (step 3 says which part runs where): the pre-review on Codex where wired (Sol
when its config names it), Fable as the same-family fallback; Gemini through Antigravity
where wired is another cross-family pre-review; the personas and a light check on Opus.

## How to report here

In this repo, a reply that reports work or asks for a decision runs **Situation** (what
is true now), **Background** (what the reader needs to judge it), **Assessment** (what
you found, with the evidence), **Recommendation** (what you would do), decisions last
(owner, 2026-10-30); a short answer needs no headings. `engineering-principles.md` §7
is the shipped part of it.

## The skills run here too

The skills are plain Markdown: `skills/<name>/SKILL.md`, plus `upstream-check`, which
maintains this repo only and lives whole, unshipped, in
`.claude/skills/upstream-check/SKILL.md`. Where a step names one (`/pre-merge-check`,
`/dg`, `/feature-start`, …), follow that file. Use them on your own changes.

## Enforcement runs from `hooks/`, not from a copy

The hooks this repo ships are the hooks it runs — the agent hooks are wired from
`hooks/agent/` (Claude Code: `.claude/settings.json`), and `core.hooksPath` is set to
`hooks/git` once per clone:

```bash
git config core.hooksPath hooks/git && git config merge.ff false
```

There is deliberately no `.flight-rules/hooks/` copy: a copy drifted once (it was the pre-conf,
commit-only guard for weeks) and the rules repo cannot afford to run stale rules on
itself. If a change to a hook needs a matching change to what this repo runs, it
happens in the same commit, because they are the same file.

## How a rule gets in

`rules/` is injected into sessions and copied into projects, so it is the easiest place
in the repo to dump advice that costs every reader and helps none. A change there is
checked harder than code. Each added or widened item must pass all four, in the PR:

1. **Names the warrant** — the reason to believe the failure in point 2 is real rather
   than plausible. One of:
   **(a) an event** — a commit, PR, sha, date, or a probe that showed the hole (for a
   refusal or a check, one a slip could also reach: `MISSION.md` question 1). It does
   not have to be public: a private-repo sha and date is a citation (`ATTRIBUTIONS.md`
   already carries one).
   **(b) an upstream** this playbook adapts from, with an `UPSTREAMS.md` row pinned at
   the ref actually reviewed. This is the strongest warrant in the corpus, because a
   reader can check it without trusting the author — which an incident from the
   author's own session never is.
   **(c) the failure description itself**, where neither exists — a rule learned
   somewhere that produced no artifact. Say so explicitly, so a reader knows the
   evidence is testimony and can weigh it as such.
   Never sufficient: a benefit with no failure attached, or "best practice".
2. **Says what goes wrong without it**, concretely. If the honest answer is "nothing
   much", it does not go in.
3. **Says how it is enforced** — a hook, a CI check, or a skill with the check number. "Advisory"
   is an answer only with the reason the item cannot be checked. Each release asks
   again whether enforcement has become possible. An item is cut only when its warrant
   is gone or another item covers it — never for being advisory, or for not having
   fired lately (owner's call, 2026-10-11: read literally, an expiry would have cut
   eleven earned principles at that release).
4. **Survives adversarial review** — `/dg` on the diff, preferring a reviewer from a
   different model family than the author (the skill says why), with the verdict in
   the PR body and each finding's disposition, applied or declined with a reason.

`pre-merge-check` item 18 asks for 1–3 on any diff to a rules file (item 18 and
`.ai/skills/pre-merge-check/EXTENSIONS.md` list them). A deletion or
tightening skips the four points but still names what it drops and where that is now
covered — a widening framed as a "fold" is how coverage quietly disappears. The same
questions are put to every bullet of `engineering-principles.md` at each release: it
is injected into every session, so it is where an unearned line costs the most. That
review reads the file as the assistant receiving it — what a bullet's literal reading
would make it do, which bullets pull against each other, what is missing — not only
whether its paperwork is in order. The file stays assistant-agnostic: it reaches every
assistant, in projects that know nothing of this repo.

## When editing a hook

- Run every suite in `{TEST_COMMANDS}` before and after; add a case for every gap you
  close. A guard that silently stops matching is worse than none — the tests exist to
  make that loud.
- Verify against the running hook, not by reading the regex. Several past gaps were
  invisible on paper (column-zero secrets, `git -C … commit`, macOS `grep -P`).
- An assertion satisfied by NO output — "allowed", "not reported", "silent" — is also
  satisfied by a hook that died before deciding. Check the exit status too, or pair it
  with an assertion over the same run that the hook said something. The suites do this
  now; keep it when you add a case.
- Cross the shapes, do not sample them. A case per matcher and a case per shell wrapper
  leaves the combinations untested, and that is where the bugs have actually been: on
  2026-09-10 six matchers were denied bare and allowed inside `( … )`, and a bypass and
  a false positive both lived in compound commands. `pre-commit-check.test.sh` generates
  the wrapper × core product for this reason — add to those lists, not a one-off case.
- macOS ships BSD `grep`, `sed` and bash 3.2. CI runs the suites on both macOS and
  Ubuntu; do not use `grep -P`, `mapfile`, or `sed -i` without a suffix.
- Hook behaviour changed? Say so in the PR body. The `.claude-plugin/plugin.json` bump
  happens once per release, on a `chore/release-<v>` branch — see **Releasing** above — never in a feature PR.
